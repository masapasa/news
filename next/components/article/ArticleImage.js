import { useEffect, useState } from 'react';

import LazyImage from '@/ui/LazyImage';

export default function ArticleImage({ article, imageSizes, sizes, className }) {
  const [ imageSrc, setImageSrc ] = useState('');
  const [ imageSrcSet, setImageSrcSet ] = useState(null);

  useEffect(() => {
    if (article && article.image && article.image.startsWith('public/')) {
      const imageUrl = `${process.env.NEXT_PUBLIC_CONTENT_API}/image/${article.id}`;

      if (sizes) {
        let _srcSet = [];
        for (let s of imageSizes) {
          _srcSet.push(`${imageUrl}?size=${s} ${s}w`);
        }
        setImageSrcSet(_srcSet.join(','));
      }
      setImageSrc(imageUrl);
    } else {
      // old image URI, served from blog cdn
      setImageSrc(article.image);
    }
  }, [ article ]);

  return (
    <LazyImage src={ imageSrc }
        alt={ article ? article.title : ' ' }
        srcset={ imageSrcSet }
        sizes={ sizes }
        className={ className } />
  );
}