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

class Player < ActiveRecord::Base
  has_many :statistics

  connection.create_table table_name, :force => true do |t|
    t.string :name
  end
end

class Statistic < ActiveRecord::Base
  belongs_to :player
  belongs_to :participant

  connection.create_table table_name, :force => true do |t|
    t.integer :player_id
    t.integer :participant_id
    t.integer :points
    t.integer :time_played
  end
end

class Participant < ActiveRecord::Base
  has_one :statistic

  scope :home_games, -> { where(homeaway: 'H') }
  scope :away_games, -> { where(homeaway: 'A') }

  connection.create_table table_name, :force => true do |t|
    t.string :homeaway
  end
end

describe 'nested where clauses' do
  before :all do
    [Statistic, Participant, Player].each { |ar| ar.delete_all }

    ActiveRecord::Base.logger = nil

    player = Player.create!(name: 'Dak Prescott')

    part_a = Participant.create!(homeaway: 'H')
    part_b = Participant.create!(homeaway: 'H')
    part_c = Participant.create!(homeaway: 'A')

    Statistic.create!(points: 10, time_played: 60, player: player, participant: part_a)
    Statistic.create!(points: 14, time_played: 60, player: player, participant: part_b)
    Statistic.create!(points: 21, time_played: 60, player: player, participant: part_c)

    ActiveRecord::Base.logger = Logger.new(STDERR)
  end

  it 'sql' do
    sql = <<-_
      SELECT name, points
      FROM players p INNER JOIN statistics s 
        ON p.id = s.player_id INNER JOIN participants pa
        ON s.participant_id = pa.id
      WHERE (pa.homeaway="H" AND s.points > 12) OR (pa.homeaway="A")
    _
    result = Player.connection.execute(sql)
    result.length.must_equal 2
    assert_row(result.first, {name: 'Dak Prescott', points: 14})
    assert_row(result.last, {name: 'Dak Prescott', points: 21})
  end

  it 'arel' do
    base = Player.select("name, points").joins(statistics: [:participant])
    result = base.where(participants: {homeaway: 'H'})
               .where("statistics.points > ?", 12)
               .or(base.where(participants: {homeaway: 'A'}))

    result.length.must_equal 2
    assert_row(result.first, {name: 'Dak Prescott', points: 14})
    assert_row(result.last, {name: 'Dak Prescott', points: 21})
  end

  it 'scopes' do
    base = Player.select("name, points").joins(statistics: [:participant])
    result = base.merge(Participant.home_games)
               .where("statistics.points > ?", 12)
               .or(base.merge(Participant.away_games))

    result.length.must_equal 2
    assert_row(result.first, {name: 'Dak Prescott', points: 14})
    assert_row(result.last, {name: 'Dak Prescott', points: 21})
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