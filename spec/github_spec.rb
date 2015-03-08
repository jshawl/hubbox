require 'spec_helper'
require_relative '../github'


describe Github do
  it "queries an api" do
    uri = URI('https://api.github.com/repos/thoughtbot/factory_girl/contributors')
    response = Net::HTTP.get(uri)
    expect(response).to be_an_instance_of(String)
  end
end