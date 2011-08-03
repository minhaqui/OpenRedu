require 'spec_helper'
require 'authlogic/test_case'
include Authlogic::TestCase

describe PlansController do
  context "for User" do
    before do
      @user = Factory(:user)
      @course = Factory(:course, :owner => @user)
      @plan = Factory(:plan, :user => @user, :billable => @course)

      activate_authlogic
      UserSession.create @user
    end

    context "when GET index" do
      before do
        get :index, :user_id => @user.login, :locale => "pt-BR"
      end

      it "should assign plans" do
        assigns[:plans].should_not be_nil
        assigns[:plans].should include(@plan)
      end

      it "renders the correct template" do
        response.should render_template('plans/index')
      end
    end
  end
end
