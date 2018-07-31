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

describe 'controlling AND OR precedence' do
  before :all do
    [Statistic, Participant, Player].each { |ar| ar.delete_all }

    ActiveRecord::Base.logger = nil

    p = Player.create!(name: 'Dak Prescott')

    Statistic.create!(points: 36, time_played: 60, player: p, participant: Participant.create!(homeaway: 'H'))
    Statistic.create!(points: 18, time_played: 60, player: p, participant: Participant.create!(homeaway: 'H'))
    Statistic.create!(points: 24, time_played: 60, player: p, participant: Participant.create!(homeaway: 'H'))

    ActiveRecord::Base.logger = Logger.new(STDERR)
  end

  it 'sql' do
    sql = <<-_
      SELECT name, points
      FROM players p INNER JOIN statistics s 
        ON p.id = s.player_id INNER JOIN participants pa
        ON s.participant_id = pa.id
      WHERE pa.homeaway="H" AND (s.points < 20 OR s.points > 30)    
      ORDER BY s.points
    _
    result = Player.connection.execute(sql)
    result.length.must_equal 2
    assert_row(result.first, {name: 'Dak Prescott', points: 18})
    assert_row(result.last, {name: 'Dak Prescott', points: 36})
  end

  # AND is higher precedence than OR, so use `merge` to ensure a higher precedent
  # OR gets processed first.
  it 'ar and scopes' do
    base = Player.select("name, points").joins(statistics: [:participant])
    result = base.merge(Participant.home_games)
               .merge(base.where("statistics.points < ?", 20)
                        .or(base.where("statistics.points > ?", 30)))
               .order("statistics.points")

    result.length.must_equal 2
    assert_row(result.first, {name: 'Dak Prescott', points: 18})
    assert_row(result.last, {name: 'Dak Prescott', points: 36})
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