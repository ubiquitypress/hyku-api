# frozen_string_literal: true
require 'rails_helper'

RSpec.describe Hyku::API::V1::SessionsController, type: :request, clean: true, multitenant: true do
  let(:user) { create(:user) }
  let(:account) { create(:account) }
  let(:json_response) { JSON.parse(response.body) }
  let(:jwt_cookie) { response.cookies.with_indifferent_access[:jwt] }
  let(:jwt_cookie_details) { cookies.send(:hash_for, nil).fetch('jwt', nil) }
  let(:refresh_cookie) { response.cookies.with_indifferent_access[:refresh] }
  let(:hyku_session_cookie) { response.cookies.with_indifferent_access[:_hyku_session] }

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

  describe "/login" do
    let(:email_credentials) { user.email }
    let(:password_credentials) { user.password }

    context 'with valid credentials' do
      it 'returns jwt token and json response' do
        post hyku_api.v1_tenant_users_login_path(tenant_id: account.tenant), params: {
          email: email_credentials,
          password: password_credentials,
          expire: 2
        }
        expect(response.status).to eq(200)
        expect(json_response['email']).to eq(user.email)
        expect(json_response['participants']).to eq []
        expect(json_response['type']).to eq []
        expect(jwt_cookie).to be_truthy
        expect(refresh_cookie).to be_truthy
        expect(hyku_session_cookie).to be_truthy
      end

      context 'with type and participants' do
        let(:user) { create(:admin) }
        let(:admin_set) { create(:admin_set, with_permission_template: true) }
        let(:permission_template_access) do
          create(:permission_template_access,
                 :manage,
                 permission_template: admin_set.permission_template,
                 agent_type: 'user',
                 agent_id: user.user_key)
        end

        before do
          Apartment::Tenant.switch(account.tenant) { permission_template_access }
        end

        it 'returns jwt token and json response' do
          post hyku_api.v1_tenant_users_login_path(tenant_id: account.tenant), params: {
            email: email_credentials,
            password: password_credentials,
            expire: 2
          }
          expect(response.status).to eq(200)
          expect(json_response['email']).to eq(user.email)
          expect(json_response['participants']).to eq [{ admin_set.title.first => "manage" }]
          expect(json_response['type']).to eq ['admin']
          expect(jwt_cookie).to be_truthy
          expect(refresh_cookie).to be_truthy
          expect(hyku_session_cookie).to be_truthy
        end
      end
    end

    context 'with invalid credentials' do
      let(:password_credentials) { '' }

      it 'does not return jwt token' do
        post hyku_api.v1_tenant_users_login_path(tenant_id: account.tenant), params: {
          email: email_credentials,
          password: password_credentials,
          expire: 2
        }
        expect(response.status).to eq(401)
        expect(json_response['status']).to eq(401)
        expect(json_response['message']).to eq("Invalid email or password.")
        expect(jwt_cookie).to be_falsey
        expect(refresh_cookie).to be_falsey
        expect(hyku_session_cookie).to be_falsey
      end
    end
  end

  describe ".cookies" do
    before do
      host! 'subdomain.domain.com'
      allow(account).to receive(:attributes).and_return(frontend_url: frontend_url)
      allow(Account).to receive(:find_by).and_return(account)
      post hyku_api.v1_tenant_users_login_path(tenant_id: account.tenant), params: {
        email: user.email,
        password: user.password,
        expire: 2
      }
      sleep(1)
    end

    context "for a valid frontend_url" do
      let(:frontend_url) { "domain.com" }

      it "sets the frontend_url as domain" do
        expect(jwt_cookie_details.domain).to eq ".#{frontend_url}"
      end
    end

    context "for no frontend_url" do
      let(:frontend_url) { nil }

      it "sets the request host as domain" do
        expect(jwt_cookie_details.domain).to eq '.subdomain.domain.com'
      end
    end
  end

  describe '/log_out' do
    before do
      post hyku_api.v1_tenant_users_login_path(tenant_id: account.tenant), params: {
        email: user.email,
        password: user.password,
        expire: 2
      }
    end

    it 'successfully logs out' do
      delete hyku_api.v1_tenant_users_log_out_path(tenant_id: account.tenant)
      expect(response.status).to eq(200)
      expect(json_response['message']).to eq("Successfully logged out")
      expect(jwt_cookie).to be_falsey
      expect(refresh_cookie).to be_falsey
    end
  end

  describe "/refresh" do
    let(:auth_header) { { "Authorization" => "Bearer #{refresh_cookie}" } }
    context 'with an unexpired refresh token' do
      before do
        post hyku_api.v1_tenant_users_login_path(tenant_id: account.tenant), params: {
          email: user.email,
          password: user.password,
          expire: 2
        }
      end

      it "refreshes the jwt token" do
        sleep(1)
        expect { post hyku_api.v1_tenant_users_refresh_path(tenant_id: account.tenant), headers: auth_header }.to change { response.cookies.with_indifferent_access[:jwt] }
      end

      it "refreshes the refresh token" do
        sleep(1)
        expect { post hyku_api.v1_tenant_users_refresh_path(tenant_id: account.tenant), headers: auth_header }.to change { response.cookies.with_indifferent_access[:refresh] }
      end

      it 'returns jwt token and json response' do
        sleep(1)
        post hyku_api.v1_tenant_users_refresh_path(tenant_id: account.tenant), headers: { "Authorization" => "Bearer #{response.cookies.with_indifferent_access[:refresh]}" }
        expect(response.status).to eq(200)
        expect(json_response['email']).to eq(user.email)
        expect(json_response['participants']).to eq []
        expect(json_response['type']).to eq []
        expect(jwt_cookie).to be_truthy
        expect(hyku_session_cookie).to be_truthy
        expect(response.cookies.with_indifferent_access[:refresh]).to be_truthy
      end

      context 'with type and participants' do
        let(:user) { create(:admin) }
        let(:admin_set) { create(:admin_set, with_permission_template: true) }
        let(:permission_template_access) do
          create(:permission_template_access,
                 :manage,
                 permission_template: admin_set.permission_template,
                 agent_type: 'user',
                 agent_id: user.user_key)
        end

        before do
          Apartment::Tenant.switch(account.tenant) { permission_template_access }
        end

        it 'returns jwt token and json response' do
          sleep(1)
          post hyku_api.v1_tenant_users_refresh_path(tenant_id: account.tenant), headers: { "Authorization" => "Bearer #{refresh_cookie}" }
          expect(response.status).to eq(200)
          expect(json_response['email']).to eq(user.email)
          expect(json_response['participants']).to eq [{ admin_set.title.first => "manage" }]
          expect(json_response['type']).to eq ['admin']
        end
      end
    end

    context 'with an expired refresh token' do
      before do
        post hyku_api.v1_tenant_users_login_path(tenant_id: account.tenant), params: {
          email: user.email,
          password: user.password,
          expire: 2
        }
      end

      it 'returns an error' do
        travel_to(Time.now.utc + 4.weeks) do
          post hyku_api.v1_tenant_users_refresh_path(tenant_id: account.tenant), headers: { "Authorization" => "Bearer #{refresh_cookie}" }
          expect(response.status).to eq(401)
          expect(json_response['status']).to eq(401)
          expect(json_response['message']).to eq("Invalid token")
          expect(jwt_cookie).to be_falsey
          expect(response.cookies.with_indifferent_access[:refresh]).to be_falsey
        end
      end
    end
  end

  describe "show" do
    let(:auth_header) { { "Authorization" => "Bearer #{refresh_cookie}" } }
    context 'with an unexpired refresh token' do
      before do
        post hyku_api.v1_tenant_users_login_path(tenant_id: account.tenant), params: {
          email: user.email,
          password: user.password,
          expire: 2
        }
      end
      it 'returns the json response' do
        sleep(1)
        post hyku_api.v1_tenant_users_current_path(tenant_id: account.tenant), headers: { "Authorization" => "Bearer #{response.cookies.with_indifferent_access[:jwt]}" }
        expect(response.status).to eq(200)
        expect(json_response['email']).to eq(user.email)
        expect(json_response['participants']).to eq []
        expect(json_response['type']).to eq []
      end
    end

    context 'with an invalid token' do
      it 'returns the json response' do
        sleep(1)
        post hyku_api.v1_tenant_users_current_path(tenant_id: account.tenant), headers: { "Authorization" => "Bearer foobar" }
        expect(response.status).to eq(401)
        expect(json_response['email']).to be_blank
        expect(json_response['participants']).to be_blank
        expect(json_response['type']).to be_blank
      end
    end
  end
end
