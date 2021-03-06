# frozen_string_literal: true

require 'test_helper'

class ThingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    stub_request(:get, 'https://maps.google.com/maps/api/geocode/json').
      with(query: {latlng: '42.383339,-71.049226', sensor: 'false'}).
      to_return(body: File.read(File.expand_path('../fixtures/city_hall.json', __dir__)))

    @thing = things(:thing_1)
    @user = users(:dan)
  end

  test 'should list drains' do
    get things_url, params: {lat: 42.358431, lng: -71.059773, format: :json}
    assert_not_nil assigns :things
    assert_response :success
  end

  test 'should 404 if there are no drains' do
    Thing.all.map(&:destroy!)
    get things_url, params: {lat: 43.358431, lng: -71.059773, format: :json}
    assert_response :missing
    assert_equal ['Could not find drain.'], JSON.parse(response.body)['errors']['address']
  end

  test 'should return true if a drain is owned by logged in user' do
    sign_in @user
    @thing.user_id = @user.id
    get things_url, params: {lat: 42.358431, lng: -71.059773, format: :json}
    assert_not_nil assigns :things
    assert_response :success
  end

  test 'should update drain display name' do
    sign_in @user
    assert_not_equal 'Birdsill', @thing.display_name
    put things_url, params: {id: @thing.id, thing: {user_id: @user.id, adopted_name: 'Birdsill'}, format: :json}
    @thing.reload
    assert_equal 'Birdsill', @thing.display_name
    assert_not_nil assigns :thing
    assert_response :success
  end

  test 'should error when updating drain with invalid data' do
    Thing.stub(:find, @thing) do
      @thing.stub(:update, false) do
        put things_url, params: {id: @thing.id, thing: {adopted_name: 'hello'}, format: :json}
      end
    end
    assert_response :error
  end

  test 'should update drain and send an adopted confirmation email' do
    sign_in @user
    num_deliveries = ActionMailer::Base.deliveries.size
    put things_url, params: {id: @thing.id, thing: {adopted_name: 'Drain', user_id: @user.id}, format: :json}
    assert @thing.reload.adopted?
    assert_equal num_deliveries + 1, ActionMailer::Base.deliveries.size
    assert_response :success

    email = ActionMailer::Base.deliveries.last
    assert_equal [@user.email], email.to
    assert_equal 'Thanks for adopting a drain, Dan!', email.subject
  end

  test 'should send second confirmation email' do
    sign_in @user
    @user.things = [things(:thing_2)]
    put things_url, params: {id: @thing.id, thing: {adopted_name: 'Drain', user_id: @user.id}, format: :json}
    assert @thing.reload.adopted?
    assert_response :success

    email = ActionMailer::Base.deliveries.last
    assert_equal [@user.email], email.to
    assert_equal 'Thanks for adopting another drain, Dan!', email.subject
  end

  test 'should update drain but not send an adopted confirmation email upon abandonment' do
    sign_in @user
    num_deliveries = ActionMailer::Base.deliveries.size
    put things_url, params: {id: @thing.id, thing: {adopted_name: 'Another Drain', user_id: nil}, format: :json} # a nil user_id is an abandonment
    assert_not @thing.reload.adopted?
    assert_equal num_deliveries, ActionMailer::Base.deliveries.size
    assert_response :success
  end
end
