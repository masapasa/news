#
# Article Model
#
require 'aws-record'
require 'aws-sdk-s3'
require 'digest'
require 'httparty'
require 'nokogiri'
require 'reverse_markdown'

# S3 client
$s3_client = Aws::S3::Client.new

class Article
  include Aws::Record

  # attributes
  string_attr   :__typename, default_value: 'Article'
  integer_attr  :_version, default_value: 1  # Amplify DataStore
  integer_attr  :_lastChangedAt, default_value: Time.now.to_i  # Amplify DataStore
  string_attr   :id, hash_key: true
  string_attr   :blogId
  string_attr   :title
  string_attr   :url
  boolean_attr  :published, default_value: false
  datetime_attr :publishedAt, default_value: Time.now
  string_attr   :author
  string_attr   :contentUri
  string_attr   :image
  string_attr   :excerpt
  list_attr     :tags

  class << self
    #
    # Find Article item by `id` or `url`.
    #
    def find(id:nil, url:nil)
      unless (id || url)
        throw new Aws::Record::Errors::KeyMissing("Must provide a valid identifier")
      end

      if url
        id = Digest::MD5.hexdigest(url)
      end

      query(
        key_condition_expression: "id = :id",
        expression_attribute_values: {
          ':id' => id
        },
        limit: 1
      ).first
    end

    #
    # Determine if an Article exists by `id` or `url`.
    #
    def exists?(id:nil, url:nil)
      !!Article.find(id: id, url: url)
    end

    #
    # Create a new Article from a Feedjira entry.
    #
    def create_from(entry:, blog_id:, content_bucket:)
      article = Article.new(
        blogId: blog_id,
        url: entry.url,
        title: entry.title,
        author: entry.author,
        publishedAt: entry.published,
        excerpt: entry.summary || '',
        tags: entry.categories
      )

      begin
        Article.write_content_to_s3(content_bucket, article.get_content_key, entry.content)
        article.image = Article.get_main_image(article.url)
      rescue Aws::S3::Errors::ServiceError => e
        p " -- FAILED TO STORE CONTENT: #{e.message}"
        raise
      rescue StandardError => e
        p " -- FAILED TO CREATE NEW ARTICLE: #{e.message}"
        raise
      end

      article.contentUri = "#{article.get_content_key}.md"
      article.published = true
      article.save!

      article
    end

    protected
    # Converts content to Markdown and writes to S3.
    def write_content_to_s3(bucket, key, content)
      $s3_client.put_object({
        body: ReverseMarkdown.convert(sanitize_content content),
        bucket: bucket,
        key: "public/#{key}.md"
      })
    end

    # Replace offending characters with ASCII equivalents
    def sanitize_content(content)
      bad_chars_replacements = {
        '“' => '"',  # 0x201c
        '”' => '"',  # 0x201d
        '’' => '\'', # 0x72
        '’' => '\'', # 0x74
        '—' => '-',  # 0x77
        '–' => '-',  # 0x20

      }

      opts = {
        invalid: :replace,
        replace: '',
        # handle any other character
        fallback: lambda { |char|
          # if no replacement, use a blank
          bad_chars_replacements.fetch(char, '')
        }
      }

      content.encode(Encoding.find('ASCII'), opts)
    end

    # Retreive the main image, included as metadata in the HTML source
    def get_main_image(url)
      page = HTTParty.get(url)
      doc = Nokogiri::HTML(page)

      image_path = doc.xpath('/html/head/meta[@property="og:image"]/@content')
      if image_path.length > 0 && !image_path.first.value.empty?
        return image_path.first.value
      end

      nil
    end
  end

  def initialize(attr_values = {})
    super

    if (self.id.nil? && !self.url.nil?)
      self.id = Digest::MD5.hexdigest(self.url)
    end

    self
  end

  def get_content_key
    "#{self.publishedAt.year}/#{self.publishedAt.month}/#{self.id}"
  end
end
