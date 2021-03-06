# frozen_string_literal: true
require 'rails_helper'

RSpec.describe Hyku::API::V1::CollectionController, type: :request, clean: true, multitenant: true do
  let(:account) { create(:account, name: 'test') }
  let(:user) { create(:user) }
  let(:json_response) { JSON.parse(response.body) }

  before do
    WebMock.disable!
    Apartment::Tenant.create(account.tenant)
    Apartment::Tenant.switch(account.tenant) do
      Site.update(account: account)
      user # force creating the user in the account
    end
  end

  after do
    WebMock.enable!
    Apartment::Tenant.drop(account.tenant)
  end

  describe "/collection" do
    context 'when repository is empty' do
      it 'returns error' do
        get "/api/v1/tenant/#{account.tenant}/collection"
        expect(response.status).to eq(200)
        expect(json_response).to include('status' => 404,
                                         'code' => 'not_found',
                                         'message' => 'This tenant has no collection')
      end
    end

    context 'when repository has content' do
      let(:collection) { create(:collection, visibility: 'open') }

      before do
        Apartment::Tenant.switch(account.tenant) { collection }
      end

      it 'returns collections' do
        get "/api/v1/tenant/#{account.tenant}/collection"
        expect(response.status).to eq(200)
        expect(json_response['total']).to eq 1
        expect(json_response['items'][0]['uuid']).to eq collection.id
        expect(response).to render_template('api/v1/collection/_collection')
      end
    end

    context 'when not logged in' do
      let(:collection) { create(:collection, visibility: 'restricted') }

      before do
        Apartment::Tenant.switch(account.tenant) { collection }
      end

      it 'does not return restricted items' do
        get "/api/v1/tenant/#{account.tenant}/collection"
        expect(response.status).to eq(200)
        expect(json_response).to include('total' => 0,
                                         'items' => [])
      end
    end

    context 'when logged in' do
      let(:collection) { create(:collection, visibility: 'restricted') }
      let(:user) { create(:admin) }

      before do
        Apartment::Tenant.switch(account.tenant) { collection }

        post hyku_api.v1_tenant_users_login_path(tenant_id: account.tenant), params: {
          email: user.email,
          password: user.password,
          expire: 2
        }
      end

      it 'returns restricted items' do
        get "/api/v1/tenant/#{account.tenant}/collection", headers: { "Cookie" => response['Set-Cookie'] }
        expect(response.status).to eq(200)
        expect(json_response['total']).to eq 1
        expect(json_response['items'][0]['uuid']).to eq collection.id
        expect(response).to render_template('api/v1/collection/_collection')
      end
    end

    context 'with per_page' do
      let(:collection1) { create(:collection, visibility: 'open') }
      let(:collection2) { create(:collection, visibility: 'open') }
      let(:per_page) { 1 }

      before do
        Apartment::Tenant.switch(account.tenant) do
          collection1
          collection2
        end
      end

      it 'limits the number of returned collections' do
        get "/api/v1/tenant/#{account.tenant}/collection?per_page=#{per_page}"
        expect(response.status).to eq(200)
        expect(json_response['total']).to eq 2
        expect(json_response['items'].size).to eq 1
      end
    end
  end

  describe "/collection/:id" do
    context 'with invalid id' do
      let(:id) { 'bad-id' }

      it 'returns error' do
        get "/api/v1/tenant/#{account.tenant}/collection/#{id}"
        expect(response.status).to eq(200)
        expect(json_response).to include('status' => 404,
                                         'code' => 'not_found',
                                         'message' => "This is either a private collection or there is no record with id: #{id}")
      end
    end

    context 'with open collection' do
      let(:collection) { create(:collection, visibility: 'open') }

      before do
        Apartment::Tenant.switch(account.tenant) { collection }
      end

      it 'returns collection json' do
        get "/api/v1/tenant/#{account.tenant}/collection/#{collection.id}"
        expect(response.status).to eq(200)
        expect(json_response).to include('uuid' => collection.id,
                                         'type' => 'collection',
                                         'related_url' => nil,
                                         'title' => collection.title.first,
                                         'resource_type' => nil,
                                         'date_created' => nil,
                                         'cname' => account.cname,
                                         'description' => nil,
                                         'date_published' => nil,
                                         'keywords' => nil,
                                         'license_for_api_tesim' => nil,
                                         'rights_statements_for_api_tesim' => nil,
                                         'language' => nil,
                                         'publisher' => nil,
                                         'thumbnail_url' => nil,
                                         'visibility' => 'open',
                                         'total_works' => 0,
                                         'works' => [],
                                         'volumes' => nil,
                                         'thumbnail_base64_string' => nil)
        expect(response).to render_template('api/v1/collection/_collection')
      end

      context 'with thumbnail' do
        let(:file_with_image) { create(:api_file_set, :public, :image) }

        before do
          collection.thumbnail_id = file_with_image.id
          collection.save!
          # FIXME: collection.thumbnail_path is still the default collection icon due to the file not getting a derivative generated
        end

        it 'returns work json' do
          get "/api/v1/tenant/#{account.tenant}/collection/#{collection.id}"
          expect(response.status).to eq(200)
          expect(json_response).to include("thumbnail_url" => URI.join("http://#{account.cname}", collection.to_solr['thumbnail_path_ss']).to_s)
        end
      end
    end

    context 'when not logged in' do
      let(:collection) { create(:collection, visibility: 'restricted') }

      before do
        Apartment::Tenant.switch(account.tenant) { collection }
      end

      it 'does not return restricted collection' do
        get "/api/v1/tenant/#{account.tenant}/collection/#{collection.id}"
        expect(response.status).to eq(200)
        expect(json_response).to include('status' => 404,
                                         'code' => 'not_found',
                                         'message' => "This is either a private collection or there is no record with id: #{collection.id}")
      end
    end

    context 'when logged in' do
      let(:collection) { create(:collection, visibility: 'restricted') }
      let(:user) { create(:admin) }

      before do
        Apartment::Tenant.switch(account.tenant) { collection }

        post hyku_api.v1_tenant_users_login_path(tenant_id: account.tenant), params: {
          email: user.email,
          password: user.password,
          expire: 2
        }
      end

      it 'returns restricted items' do
        get "/api/v1/tenant/#{account.tenant}/collection/#{collection.id}", headers: { "Cookie" => response['Set-Cookie'] }
        expect(response.status).to eq(200)
        expect(json_response['uuid']).to eq collection.id
        expect(response).to render_template('api/v1/collection/_collection')
      end
    end
  end

  describe "Member works" do
    let(:public_work) { create(:work, visibility: 'open', member_of_collections: [collection]) }
    let(:institution_work) { create(:work, visibility: 'authenticated', member_of_collections: [collection]) }
    let(:private_work) { create(:work, visibility: 'restricted', member_of_collections: [collection]) }
    let(:collection_works) { [public_work, institution_work, private_work] }

    before do
      Apartment::Tenant.switch(account.tenant) do
        collection
        collection_works if collection.present?
      end
    end

    context 'with open collection' do
      let(:collection) { create(:collection, visibility: 'open') }
      let(:collection_works) { [public_work] }

      it 'returns works within the collection' do
        get "/api/v1/tenant/#{account.tenant}/collection/#{collection.id}"
        expect(response.status).to eq(200)
        expect(json_response['total_works']).to eq 1
        expect(json_response['works'].size).to eq 1
        expect(json_response['works'][0]).to include('uuid' => public_work.id)
        expect(response).to render_template('api/v1/work/_work')
      end
    end

    context 'when not logged in' do
      context 'with public collection' do
        let(:collection) { create(:collection, visibility: 'open') }

        it 'returns only public files for open works' do
          get "/api/v1/tenant/#{account.tenant}/collection/#{collection.id}"
          expect(response.status).to eq(200)
          expect(json_response['total_works']).to eq 1
          expect(json_response['works'].size).to eq 1
          expect(json_response['works'][0]).to include('uuid' => public_work.id)
          expect(response).to render_template('api/v1/work/_work')
        end
      end
    end

    context 'when logged in' do
      let(:collection) { create(:collection, visibility: 'restricted') }
      let(:collection_works) { [private_work] }
      let(:user) { create(:admin) }

      before do
        post hyku_api.v1_tenant_users_login_path(tenant_id: account.tenant), params: {
          email: user.email,
          password: user.password,
          expire: 2
        }
      end

      it 'returns restricted items' do
        get "/api/v1/tenant/#{account.tenant}/collection/#{collection.id}", headers: { "Cookie" => response['Set-Cookie'] }
        expect(response.status).to eq(200)
        expect(json_response['total_works']).to eq 1
        expect(json_response['works'].size).to eq 1
        expect(json_response['works'][0]).to include('uuid' => private_work.id)
        expect(response).to render_template('api/v1/work/_work')
      end

      context 'as a non-admin user' do
        let(:user) { create(:user) }
        let(:collection) { create(:collection, visibility: 'authenticated') }
        let(:collection_works) { [institution_work, private_work] }

        it 'returns only public works' do
          get "/api/v1/tenant/#{account.tenant}/collection/#{collection.id}"
          expect(response.status).to eq(200)
          expect(json_response['total_works']).to eq 1
          expect(json_response['works'].size).to eq 1
          expect(json_response['works'][0]).to include('uuid' => institution_work.id)
          expect(response).to render_template('api/v1/work/_work')
        end
      end
    end

    context 'with per_page' do
      let(:collection) { create(:collection, visibility: 'open') }
      let(:per_page) { 1 }
      let(:public_work2) { create(:work, visibility: 'open', member_of_collections: [collection]) }
      let(:collection_works) { [public_work, public_work2] }

      it 'limits the number of returned works' do
        get "/api/v1/tenant/#{account.tenant}/collection/#{collection.id}?per_page=#{per_page}"
        expect(response.status).to eq(200)
        expect(json_response['total_works']).to eq 2
        expect(json_response['works'].size).to eq 1
        expect(json_response['works'][0]).to include('uuid' => public_work.id)
        expect(response).to render_template('api/v1/work/_work')
      end

      context 'with page' do
        let(:page) { 2 }

        it 'limits the number of returned works and offsets to page' do
          get "/api/v1/tenant/#{account.tenant}/collection/#{collection.id}?per_page=#{per_page}&page=#{page}"
          expect(response.status).to eq(200)
          expect(json_response['total_works']).to eq 2
          expect(json_response['works'].size).to eq 1
          expect(json_response['works'][0]).to include('uuid' => public_work2.id)
          expect(response).to render_template('api/v1/work/_work')
        end
      end
    end
  end
end
