require 'rest-client'
require 'json'
require 'dotenv/load'

API_KEY = ENV['API_KEY']
ACCOUNT_ID = ENV['ACCOUNT_ID']
REGION_BASE_URL = ENV['REGION_BASE_URL']
REGION_MARKET_BASE_URL = ENV['REGION_MARKET_BASE_URL']

HEADERS = {
  'auth-token' => "#{API_KEY}",
  'Content-Type' => 'application/json'
}

# URL to get open positions
POSITIONS_URL = "#{REGION_BASE_URL}/users/current/accounts/#{ACCOUNT_ID}/positions"

# URL to place a trade (example for EURUSD)
TRADE_URL = "#{REGION_BASE_URL}/users/current/accounts/#{ACCOUNT_ID}/trade"

# URL to retrieve candles
CANDLES_URL = "#{REGION_MARKET_BASE_URL}/users/current/accounts/#{ACCOUNT_ID}/historical-market-data/symbols/ETHUSDm/timeframes/5m/candles"

# Function to get current positions
def get_candles
  begin
    response = RestClient.get(CANDLES_URL, HEADERS)
    candles = JSON.parse(response.body)
    candles
  rescue RestClient::ExceptionWithResponse => e
    puts "Error fetching candles: #{e.response}"
    nil
  end
end

def get_positions
  begin
    response = RestClient.get(POSITIONS_URL, HEADERS)
    positions = JSON.parse(response.body)
    positions
    # [
    #   {"id"=>"2975166898", "platform"=>"mt5", "type"=>"POSITION_TYPE_BUY", "symbol"=>"ETHUSDm", "magic"=>0, "time"=>"2025-11-15T14:00:24.212Z", "brokerTime"=>"2025-11-15 14:00:24.212", "updateTime"=>"2025-11-15T14:00:24.212Z", "openPrice"=>3191.77, "volume"=>0.1, "swap"=>0, "commission"=>0, "realizedSwap"=>0, "realizedCommission"=>0, "unrealizedSwap"=>0, "unrealizedCommission"=>0, "reason"=>"POSITION_REASON_MOBILE", "currentPrice"=>3182.83, "currentTickValue"=>0.01, "realizedProfit"=>0, "unrealizedProfit"=>-0.89, "profit"=>-0.89, "accountCurrencyExchangeRate"=>1, "updateSequenceNumber"=>1763215224212003},
    #   {"id"=>"2975249537", "platform"=>"mt5", "type"=>"POSITION_TYPE_BUY", "symbol"=>"ETHUSDm", "magic"=>0, "time"=>"2025-11-15T14:21:35.125Z", "brokerTime"=>"2025-11-15 14:21:35.125", "updateTime"=>"2025-11-15T14:21:35.125Z", "openPrice"=>3171.77, "volume"=>0.2, "swap"=>0, "commission"=>0, "realizedSwap"=>0, "realizedCommission"=>0, "unrealizedSwap"=>0, "unrealizedCommission"=>0, "reason"=>"POSITION_REASON_EXPERT", "currentPrice"=>3182.83, "currentTickValue"=>0.01, "realizedProfit"=>0, "unrealizedProfit"=>-0.36, "profit"=>-0.36, "accountCurrencyExchangeRate"=>1, "brokerComment"=>"Buds EA Beta version", "comment"=>"Buds EA Beta version", "updateSequenceNumber"=>1763216495125008}
    # ]
  rescue RestClient::ExceptionWithResponse => e
    puts "Error fetching positions: #{e.response}"
    nil
  end
end

# Function to place a buy order
def place_trade(type, volume, take_profit, relative_pips = false)
  order_data = {
    "actionType" => type,
    "symbol" => 'ETHUSDm',
    "volume" => volume,
    "takeProfit" => take_profit,
    "comment" => "LOTUS EA BETA TESTING"
  }

  order_data = order_data.merge("takeProfitUnits": "RELATIVE_PIPS") if relative_pips
  order_data = order_data.to_json

  begin
    response = RestClient.post(TRADE_URL, order_data, HEADERS)
    order_response = JSON.parse(response.body)
    puts "Trade placed successfully: #{order_response}"
    order_response
  rescue RestClient::ExceptionWithResponse => e
    puts "Error placing order: #{e.response}"
  end
end

def update_trade(position, take_profit)
  order_data = {
    "actionType" => 'POSITION_MODIFY',
    "positionId" => position['id'],
    "takeProfit"=> take_profit
  }.to_json

  begin
    response = RestClient.post(TRADE_URL, order_data, HEADERS)
    order_response = JSON.parse(response.body)
    puts "Position updated successfully: #{order_response}"
  rescue RestClient::ExceptionWithResponse => e
    puts "Error placing order: #{e.response}"
  end
end

def update_trades
  positions = get_positions
  prices = positions.map{|p| p['openPrice']}.sum
  take_profit = prices / (positions.size)

  positions.each do |position|
    update_trade(position, take_profit)
  end
end

# Function to decide whether to place a trade
def should_place_trade?(positions)
  latest_position = latest_position(positions)
  next_potential_position = next_potential_position(positions)
  next_potential_lot_size = first_position(positions)['volume'] * (positions.size + 1)
  latest_price = latest_position['currentPrice']
  trade_type = latest_position['type']

  if (trade_type == 'POSITION_TYPE_BUY' && next_potential_position > latest_price) || (trade_type == 'POSITION_TYPE_SELL' && next_potential_position < latest_price)
    puts "EXECUTE TRADE -> PRICE: #{latest_price}, TYPE: #{trade_type}, LOT_SIZE: #{next_potential_lot_size}"
    return true
  else
    puts "PRICE: #{latest_price}, NEXT POSITION: #{next_potential_position}, TIME: #{DateTime.now.strftime("%m/%d/%y %l:%M %p")}"
    return false
  end
end

def next_potential_position(positions)
  if latest_position(positions)['type'] == 'POSITION_TYPE_BUY'
    latest_position(positions)['openPrice'] - (10 * (positions.size + 1))
  else
    latest_position(positions)['openPrice'] + (10 * (positions.size + 1))
  end
end

def latest_position(positions)
  positions.last
end

def first_position(positions)
  positions.first
end

def next_take_profit(positions, new_position_price)
  prices = positions.map{|p| p['openPrice']}.sum + new_position_price
  prices / (positions.size + 1)
end

# Main loop to check positions every 5 minutes and place a trade if necessary
loop do
  positions = get_positions
  if positions.size > 0
    if should_place_trade?(positions)
      latest_position = latest_position(positions)
      next_potential_lot_size = first_position(positions)['volume'] * (positions.size + 1)
      trade_type = latest_position['type'] == 'POSITION_TYPE_BUY' ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL'
      take_profit = next_take_profit(positions, latest_position['currentPrice'])

      place_trade(trade_type, next_potential_lot_size, take_profit)
      update_trades # update trades so positions will be accurate and tp will be calculated correctly
    end
  else
    candles = get_candles
    short_ma = candles.last(6).map{|candle| candle['close']}.sum / 6
    long_ma = candles.last(60).map{|candle| candle['close']}.sum / 60
    
    trend = if short_ma > long_ma
      'uptrend'
    elsif short_ma < long_ma
      'downtrend'
    else
      'sideways'
    end

    puts "TREND: #{trend} (last 30 mins: #{short_ma}, last 5 hours: #{long_ma})"

    trade_type = case trend
    when 'uptrend'
      'ORDER_TYPE_BUY'
    when 'downtrend'
      'ORDER_TYPE_SELL'
    else
      nil
    end

    place_trade(trade_type, 0.1, 1000, true)
  end

  # Sleep for n seconds before checking positions again
  sleep(60)
end
