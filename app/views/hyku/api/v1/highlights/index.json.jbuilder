# frozen_string_literal: true
if @collections.present?
  json.explore_collections do
    json.partial! 'hyku/api/v1/collection/collection', collection: @collections, as: :collection, include_works: false
  end
else
  json.explore_collections nil
end

if @featured_works.present?
  json.featured_works do
    json.partial! 'hyku/api/v1/work/work', collection: @featured_works, as: :work, collection_docs: @collection_docs
  end
else
  json.featured_works nil
end

if @recent_documents.present?
  json.recent_works do
    json.partial! 'hyku/api/v1/work/work', collection: @recent_documents, as: :work, collection_docs: @collection_docs
  end
else
  json.recent_works nil
end

json.featured_order do
  json.array! @featured_works_list
end
