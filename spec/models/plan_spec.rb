require 'spec_helper'

describe Plan do
  subject { Factory(:plan) }

  it { should belong_to :billable }
  it { should belong_to :user }
  it { should have_one :changed_to }
  it { should have_many :invoices }
  it { should belong_to :changed_from }

  it { should_not allow_mass_assignment_of :state }

  [:members_limit, :price, :yearly_price].each do |attr|
    it { should validate_presence_of attr }
  end

  def period
    (Date.today.at_end_of_month - Date.today).to_i

  end

  context "states" do
    [:close!, :migrate!, :current_state].each do |attr|
      it "responds to" do
        should respond_to attr
      end
    end

    it "defaults to active" do
      subject.current_state.should == :active
    end

    it "closes" do
      expect {
        subject.close!
      }.should change { subject.current_state }.to :closed
    end

    it "migrates" do
      expect {
        subject.migrate!
      }.should change { subject.current_state }.to :migrated
    end
  end

  context "when creating new invoices" do
    it "responds to create_invoice" do
      should respond_to :create_invoice
    end

    it "should be valid" do
      invoice = subject.create_invoice()
      invoice.should be_valid
    end

    it "should be successfully" do
      per_day = subject.price / subject.days_in_current_month
      expected_amount = (period == 0) ? 0.to_d :  period * per_day

      expect {
        @invoice = subject.create_invoice()
      }.should change(subject.invoices, :count).to(1)

      @invoice.amount.round(8).should == expected_amount.round(8)
      @invoice.period_end.should == Date.today.at_end_of_month
      @invoice.period_start.should == Date.tomorrow
    end

    it "period_start defaults to tomorrow" do
      subject.create_invoice
      subject.invoices.first.period_start.should == Date.tomorrow
    end

    it "accepts custom attributes" do
      attrs = {
        :description => "Lorem ipsum dolor sit amet, consectetur magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation",
        :period_start => Date.today + 3,
        :period_end => Date.today + 5,
        :amount => "21.5"
      }

      invoice = subject.create_invoice(attrs)
      invoice.should be_valid

      # Criando instância para o caso de existir algum callback que modifique o
      # modelo
      memo = Factory.build(:invoice, attrs)

      invoice.description.should == memo.description
      invoice.period_start.should == memo.period_start
      invoice.period_end.should == memo.period_end
      invoice.amount.should == memo.amount

    end

    it "infers the amount if period_start isnt specified" do
      per_day = subject.price / subject.days_in_current_month
      expected_amount = (period == 0) ? 0.to_d : (per_day * period)

      attrs = {
        :description => "Lorem ipsum dolor sit amet, consectetur magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation",
        :period_end => Date.today + 5
      }

      invoice = subject.create_invoice(attrs)

      invoice.should be_valid
      invoice.amount.should == expected_amount
    end

    context "when generating the amount" do
      it "calculates days in a period" do
        subject.complete_days_in(Date.new(2011,01,14),
                                 Date.new(2011,01,31)).should == 17
      end

      it "responds to amount_until_next_month" do
        should respond_to :amount_until_next_month
      end

      it "should be proportionally to period until billing date" do
        per_day = subject.price / subject.days_in_current_month
        expected_amount = (period == 0) ? 0.to_d : (per_day * period)

        expected_amount.should_not be_nil
        expected_amount.should == expected_amount
      end

      it "infers the amount between two dates" do
        subject.update_attribute(:price, 28)
        Date.stub(:today => Date.new(2011,02,14))

        subject.amount_between(Date.today, Date.today + 3).should == BigDecimal("3", 8)
      end
    end
  end

  context "when migrating to a new plan" do
    before do
      @amount_per_day = subject.price / subject.days_in_current_month
      subject.create_invoice(:period_start => Date.new(2011, 01, 01),
                             :period_end => Date.new(2011, 01, 31),
                             :amount =>  31 * @amount_per_day)

      subject.create_invoice(:period_start => Date.new(2011, 02, 01),
                             :period_end => Date.new(2011, 02, 28),
                             :amount =>  28 * @amount_per_day)

      @new_plan = subject.migrate_to(:name => "Novo plano",
                                     :members_limit => 30, 
                                     :price => 10,
                                     :yearly_price => 100)
    end

    it "responds to migrate_to" do
      should respond_to :migrate_to
    end

    it "sets state to migrated" do
      subject.current_state.should == :migrated
    end

    it "creates a valid and new plan" do
      subject.should be_valid
    end

    it "copies the older plan associations" do
      @new_plan.user.should == subject.user
      @new_plan.billable.should == subject.billable
    end

    it "sets changed to/from associations" do
      subject.changed_to.should == @new_plan
      @new_plan.changed_from == subject
    end

    it "preserves the original invoices" do
      subject.invoices.to_set.should be_subset(@new_plan.invoices.to_set)
    end
  end

  context "when upgrading" do
    before do
      # Garantindo que o plano atual é inferior ao próximo
      subject { Factory(:plan, :price => 50, :yearly_price => 150) }

      @amount_per_day = subject.price / subject.days_in_current_month
      subject.create_invoice(:period_start => Date.new(2011, 01, 01),
                             :period_end => Date.new(2011, 01, 31),
                             :amount =>  31 * @amount_per_day)

      subject.create_invoice(:period_start => Date.new(2011, 02, 01),
                             :period_end => Date.new(2011, 02, 28),
                             :amount =>  28 * @amount_per_day)

      subject.invoices.pending.map { |i| i.pay! }
      subject.invoices.reload

      @new_plan = subject.migrate_to(:name => "Novo plano",
                                     :members_limit => 30, 
                                     :price => 10,
                                     :yearly_price => 100)

    end

    it "creates an additional invoice on the new plan" do
      per_day = @new_plan.price / @new_plan.days_in_current_month
      invoice = @new_plan.invoices.pending.first(:conditions => {
        :period_start => Date.tomorrow,
        :period_end => Date.today.at_end_of_month})
      
      invoice.should_not be_nil
      invoice.amount.round(2).should == (period * per_day).round(2)
    end

  end

  it { should respond_to :create_order }

  context "when creating a new order" do
    it "should return a valid order object" do
      subject.create_order.should be_instance_of(PagSeguro::Order)
    end

    it "should have the plan ID" do
      subject.create_order.id == subject.id
    end

    context "with custom attributes" do
      before do
        @opts = {
          :order_id => 12,
          :items => [{:id => 13, :price => 12.0}]
        }
      end

      it "accepts custom ID" do
        order = subject.create_order(@opts)
        order.id.should == @opts[:order_id]
      end

      it "accepts custom items" do
        order = subject.create_order(@opts)
        order.products.first == @opts[:items].first
      end
    end

    context "the order" do
      before do
        invoices = 3.times.inject([]) { |res,i|
          res << Factory(:invoice, :plan => subject)
        }

        @products = subject.create_order.products
      end

      it "should have 3 products" do
        @products.should_not be_nil
        @products.size.should == 3
      end
    end
  end

  context "when creating a preset" do
    it "should respond to from_preset" do
      Plan.should respond_to(:from_preset)
    end

    it "creates a plan from preset" do
      plan = Plan.from_preset(:professor_standard)
      plan.should be_valid
    end
  end

end
