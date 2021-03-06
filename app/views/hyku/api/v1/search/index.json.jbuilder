# frozen_string_literal: true
json.total @result_count

json.items do
  json.array! @results do |result|
    if result.collection?
      json.partial! 'hyku/api/v1/collection/collection', locals: {
        collection: Hyrax::CollectionPresenter.new(result, current_ability, request),
        include_works: false
      }
    else
      json.partial! 'hyku/api/v1/work/work', work: Hyku::WorkShowPresenter.new(result, current_ability, request), collection_docs: @collection_docs
    end
  end
end

json.facet_counts @facet_counts
