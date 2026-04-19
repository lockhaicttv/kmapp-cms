import type { Schema, Struct } from '@strapi/strapi';

export interface ComponentsBanner extends Struct.ComponentSchema {
  collectionName: 'components_components_banners';
  info: {
    displayName: 'banner';
    icon: 'picture';
  };
  attributes: {
    image: Schema.Attribute.Media<'images' | 'files' | 'videos' | 'audios'>;
  };
}

export interface ComponentsCarousel extends Struct.ComponentSchema {
  collectionName: 'components_components_carousels';
  info: {
    displayName: 'carousel';
    icon: 'landscape';
  };
  attributes: {
    carousel: Schema.Attribute.Media<
      'images' | 'files' | 'videos' | 'audios',
      true
    >;
  };
}

export interface ComponentsRichText extends Struct.ComponentSchema {
  collectionName: 'components_components_rich_texts';
  info: {
    displayName: 'rich text';
  };
  attributes: {
    richText: Schema.Attribute.RichText &
      Schema.Attribute.CustomField<
        'plugin::ckeditor5.CKEditor',
        {
          preset: 'defaultHtml';
        }
      >;
  };
}

declare module '@strapi/strapi' {
  export module Public {
    export interface ComponentSchemas {
      'components.banner': ComponentsBanner;
      'components.carousel': ComponentsCarousel;
      'components.rich-text': ComponentsRichText;
    }
  }
}
