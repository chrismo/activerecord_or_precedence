require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'

  gem 'activerecord', '~> 5.0.0', '< 5.1.0'
  gem 'sqlite3'
  gem 'minitest-hooks'
end

require 'active_record'
require 'minitest/autorun'
require 'minitest/hooks/default'

ActiveRecord::Base.establish_connection :adapter => 'sqlite3', :database => ':memory:'

class Client < ActiveRecord::Base
  has_one :address
  has_many :orders

  connection.create_table table_name, :force => true do |t|
    t.string :name
    t.integer :orders_count
  end
end

class Address < ActiveRecord::Base
  belongs_to :client

  connection.create_table table_name, :force => true do |t|
    t.integer :client_id
    t.string :street
    t.string :state
  end
end

class Order < ActiveRecord::Base
  belongs_to :client

  connection.create_table table_name, :force => true do |t|
    t.integer :client_id
    t.decimal :amount
    t.string :status
  end
end

describe 'controlling AND OR precedence' do
  before :all do
    [Client, Address, Order].each { |ar| ar.delete_all }

    ActiveRecord::Base.logger = nil

    texas = Client.create!(name: "Texas Person")
    maine = Client.create!(name: "Maine Person")

    Address.create!(street: "123 Street Ave.", state: "TX", client: texas)
    Address.create!(street: "456 Main Street", state: "ME", client: maine)

    Order.create!(client: texas, status: "paid", amount: 30.00)
    Order.create!(client: texas, status: "pending", amount: 46.00)
    Order.create!(client: maine, status: "refunded", amount: 30.00)
    Order.create!(client: maine, status: "pending", amount: 120.00)

    ActiveRecord::Base.logger = Logger.new(STDERR)
  end

  it 'sql' do
    sql = <<-_
      SELECT c.name, o.amount
      FROM clients c INNER JOIN addresses a
        ON c.id = a.client_id INNER JOIN orders o
        ON c.id = o.client_id
      WHERE a.state="TX" AND (o.amount < 40 OR o.amount > 100)    
      ORDER BY o.id
    _
    result = Client.connection.execute(sql)
    result.length.must_equal 1
    assert_row(result.first, {name: 'Texas Person', amount: 30})
  end

  # AND is higher precedence than OR, so use `merge` to ensure a higher precedent
  # OR gets processed first.
  it 'ar and scopes' do
    base = Client.select("name, amount").joins(:address, :orders)
    result = base.merge(Address.where(state: "TX"))
               .merge(base.where("orders.amount < ?", 40)
                        .or(base.where("orders.amount > ?", 100)))
               .order("orders.id")

    result.length.must_equal 1
    assert_row(result.first, {name: 'Texas Person', amount: 30})
  end

  def assert_row(row, values)
    case row
    when Hash
      values.each_pair { |col, value| row[col.to_s].must_equal value }
    else
      values.each_pair { |col, value| row.send(col).must_equal value }
    end
  end
end