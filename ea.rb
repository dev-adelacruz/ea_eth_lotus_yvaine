require 'rest-client'
require 'json'
require 'dotenv/load'

# Enable immediate flushing of logs
$stdout.sync = true
$stderr.sync = true

# Custom logging function with timestamps
def log(message)
  timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
  puts "[#{timestamp}] #{message}"
end

API_KEY = ENV['API_KEY']
ACCOUNT_ID = ENV['ACCOUNT_ID']
REGION_BASE_URL = ENV['REGION_BASE_URL']
REGION_MARKET_BASE_URL = ENV['REGION_MARKET_BASE_URL']

# Enhanced configuration
ENABLE_ENHANCED_ANALYSIS = true  # Set to true to use enhanced analysis for trading

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

# Enhanced technical analysis functions

# Calculate RSI (Relative Strength Index)
def calculate_rsi(prices, period=14)
  return 50 if prices.length < period + 1  # Not enough data
  
  gains = []
  losses = []
  
  # Calculate price changes
  (1...prices.length).each do |i|
    change = prices[i] - prices[i-1]
    gains << [change, 0].max
    losses << [change.abs, 0].max
  end
  
  # Calculate average gains and losses for the period
  avg_gain = gains.last(period).sum / period.to_f
  avg_loss = losses.last(period).sum / period.to_f
  
  # Avoid division by zero
  return 50 if avg_loss == 0
  
  # Calculate RSI
  rs = avg_gain / avg_loss
  rsi = 100 - (100 / (1 + rs))
  rsi.round(2)
end

# Function to get candles for specified timeframe
def get_candles(timeframe='5m')
  candles_url = "#{REGION_MARKET_BASE_URL}/users/current/accounts/#{ACCOUNT_ID}/historical-market-data/symbols/ETHUSDm/timeframes/#{timeframe}/candles"
  
  begin
    response = RestClient.get(candles_url, HEADERS)
    candles = JSON.parse(response.body)
    candles
  rescue RestClient::ExceptionWithResponse => e
    log("Error fetching #{timeframe} candles: #{e.response}")
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
    log("Error fetching positions: #{e.response}")
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
    log("Trade placed successfully: #{order_response}")
    order_response
  rescue RestClient::ExceptionWithResponse => e
    log("Error placing order: #{e.response}")
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
    log("Position updated successfully: #{order_response}")
  rescue RestClient::ExceptionWithResponse => e
    log("Error placing order: #{e.response}")
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
    log("EXECUTE TRADE -> PRICE: #{latest_price}, TYPE: #{trade_type}, LOT_SIZE: #{next_potential_lot_size}")
    return true
  else
    log("PRICE: #{latest_price}, NEXT POSITION: #{next_potential_position}, TIME: #{DateTime.now.strftime("%m/%d/%y %l:%M %p")}")
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

# Enhanced trend analysis with RSI and multiple timeframes
def calculate_trend(candles)
  return 'sideways' if candles.nil? || candles.empty?
  
  short_ma = candles.last(6).map{|candle| candle['close']}.sum / 6
  long_ma = candles.last(60).map{|candle| candle['close']}.sum / 60
  
  if short_ma > long_ma
    'uptrend'
  elsif short_ma < long_ma
    'downtrend'
  else
    'sideways'
  end
end

# Enhanced trend analysis with RSI filtering and multiple timeframe confirmation
def enhanced_trend_analysis
  # Get candles for multiple timeframes
  candles_5m = get_candles('5m')
  candles_15m = get_candles('15m')
  candles_1h = get_candles('1h')
  
  # Calculate trends for each timeframe
  trend_5m = calculate_trend(candles_5m)
  trend_15m = calculate_trend(candles_15m)
  trend_1h = calculate_trend(candles_1h)
  
  # Calculate RSI for 5m (entry timeframe)
  prices_5m = candles_5m.map { |c| c['close'] }
  rsi_5m = calculate_rsi(prices_5m)
  
  # Determine overall trend with RSI filter
  if trend_5m == 'uptrend' && trend_15m == 'uptrend' && trend_1h == 'uptrend' && rsi_5m < 70
    { trend: 'uptrend', confidence: 'high', rsi: rsi_5m, timeframe_alignment: 'all_uptrend' }
  elsif trend_5m == 'downtrend' && trend_15m == 'downtrend' && trend_1h == 'downtrend' && rsi_5m > 30
    { trend: 'downtrend', confidence: 'high', rsi: rsi_5m, timeframe_alignment: 'all_downtrend' }
  else
    { trend: 'sideways', confidence: 'low', rsi: rsi_5m, timeframe_alignment: 'conflicting' }
  end
end

# Enhanced trading decision with comprehensive logging
def enhanced_trading_decision
  analysis = enhanced_trend_analysis
  
  # Log the enhanced analysis for testing
  log("=== ENHANCED ANALYSIS ===")
  log("Trend: #{analysis[:trend]}")
  log("Confidence: #{analysis[:confidence]}")
  log("RSI: #{analysis[:rsi]}")
  log("Timeframe Alignment: #{analysis[:timeframe_alignment]}")
  log("=========================")
  
  # Return trading decision
  case analysis[:trend]
  when 'uptrend'
    'ORDER_TYPE_BUY'
  when 'downtrend'
    'ORDER_TYPE_SELL'
  else
    nil
  end
end

# Performance tracking
$bad_trades_avoided = 0
$total_analysis_cycles = 0

# Main loop to check positions every 5 minutes and place a trade if necessary
loop do
  positions = get_positions
  $total_analysis_cycles += 1
  
  if positions.size > 0
    if should_place_trade?(positions)
      # Define variables for martingale trading
      trade_type = latest_position(positions)['type'] == 'POSITION_TYPE_BUY' ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL'
      next_potential_lot_size = first_position(positions)['volume'] * (positions.size + 1)
      take_profit = next_take_profit(positions, next_potential_position(positions))
      place_trade(trade_type, next_potential_lot_size, take_profit)
      update_trades # update trades so positions will be accurate and tp will be calculated correctly
    end
  else
    # Run both old and new analysis for comparison
    candles = get_candles('5m')
    short_ma = candles.last(6).map{|candle| candle['close']}.sum / 6
    long_ma = candles.last(60).map{|candle| candle['close']}.sum / 60
    
    # Old trend logic
    old_trend = if short_ma > long_ma
      'uptrend'
    elsif short_ma < long_ma
      'downtrend'
    else
      'sideways'
    end

    old_trade_type = case old_trend
    when 'uptrend'
      'ORDER_TYPE_BUY'
    when 'downtrend'
      'ORDER_TYPE_SELL'
    else
      nil
    end

    # Enhanced analysis (always runs for logging)
    enhanced_analysis = enhanced_trend_analysis
    enhanced_trade_type = enhanced_trading_decision
    
    # Compare signals
    log("=== SIGNAL COMPARISON ===")
    log("OLD: #{old_trend} -> #{old_trade_type}")
    log("ENHANCED: #{enhanced_analysis[:trend]} (#{enhanced_analysis[:confidence]}) -> #{enhanced_trade_type}")
    log("RSI: #{enhanced_analysis[:rsi]}")
    
    # Track bad trades avoided
    if old_trade_type != enhanced_trade_type && enhanced_analysis[:confidence] == 'high'
      if (old_trade_type == 'ORDER_TYPE_BUY' && enhanced_analysis[:rsi] > 70) || 
         (old_trade_type == 'ORDER_TYPE_SELL' && enhanced_analysis[:rsi] < 30)
        $bad_trades_avoided += 1
        log("🚫 BAD TRADE AVOIDED! (RSI extreme)")
      end
    end
    
    log("Bad trades avoided: #{$bad_trades_avoided}/#{$total_analysis_cycles}")
    log("========================")

    # Decide which system to use for actual trading
    if ENABLE_ENHANCED_ANALYSIS
      # Use enhanced analysis for trading
      if enhanced_trade_type
        place_trade(enhanced_trade_type, 0.1, 1000, true)
      else
        log("Enhanced analysis: No trade (low confidence)")
      end
    else
      # Use old system for trading (default - safe mode)
      if old_trade_type
        place_trade(old_trade_type, 0.1, 1000, true)
      end
    end
  end

  # Sleep for n seconds before checking positions again
  sleep(300)
end
