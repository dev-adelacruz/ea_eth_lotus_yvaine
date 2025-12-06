require 'rest-client'
require 'json'
require 'dotenv'
env_file = ENV['DOTENV'] || '.env'
Dotenv.load(env_file)

# Enable immediate flushing of logs
$stdout.sync = true
$stderr.sync = true

# Custom logging function with timestamps
def log(message)
  timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
  puts "YVAINE:[#{timestamp}] #{message}"
end

API_KEY = ENV['API_KEY']
ACCOUNT_ID = ENV['ACCOUNT_ID']
REGION_BASE_URL = ENV['REGION_BASE_URL']
REGION_MARKET_BASE_URL = ENV['REGION_MARKET_BASE_URL']
TAKE_PROFIT_BUFFER = ENV['TAKE_PROFIT_BUFFER']
INITIAL_LOT_SIZE = ENV['INITIAL_LOT_SIZE']
PAIR_SYMBOL = ENV['PAIR_SYMBOL']

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
CANDLES_URL = "#{REGION_MARKET_BASE_URL}/users/current/accounts/#{ACCOUNT_ID}/historical-market-data/symbols/#{PAIR_SYMBOL}/timeframes/5m/candles"

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
  candles_url = "#{REGION_MARKET_BASE_URL}/users/current/accounts/#{ACCOUNT_ID}/historical-market-data/symbols/#{PAIR_SYMBOL}/timeframes/#{timeframe}/candles"
  
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

def initial_lot_size
  INITIAL_LOT_SIZE || 0.1
end

# Function to place a buy order
def place_trade(type, volume, take_profit, relative_pips = false)
  order_data = {
    "actionType" => type,
    "symbol" => PAIR_SYMBOL,
    "volume" => volume,
    "takeProfit" => take_profit,
    "comment" => "LOTUS YVAINE BETA 0.0.1"
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
  take_profit = (prices / (positions.size)) + take_profit_buffer(first_position(positions)['type']).to_f

  positions.each do |position|
    update_trade(position, take_profit)
  end
end

def take_profit_buffer(trade_type)
  tp_buffer = TAKE_PROFIT_BUFFER || 2
  trade_type == 'POSITION_TYPE_BUY' ? (tp_buffer) : (0 - tp_buffer)
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

# Function to get daily high and low prices
def get_daily_high_low
  # Try to get 1h candles for today's intraday high/low
  candles_1h = get_candles('1h')
  if candles_1h && !candles_1h.empty?
    require 'time'
    now = Time.now.utc
    today_candles = candles_1h.select do |candle|
      candle_time = Time.parse(candle['time']).utc
      candle_time.to_date == now.to_date
    end
    
    if !today_candles.empty?
      high = today_candles.map { |c| c['high'].to_f }.max
      low = today_candles.map { |c| c['low'].to_f }.min
      log("Using intraday high/low from 1h candles: high=#{high}, low=#{low}")
      return [high, low]
    end
  end

  # Fallback to daily candle if 1h candles not available or no today's candles
  daily_candles = get_candles('1d')
  if daily_candles && !daily_candles.empty?
    today_candle = daily_candles.last
    log("Using daily candle high/low: high=#{today_candle['high']}, low=#{today_candle['low']}")
    return [today_candle['high'], today_candle['low']]
  end

  log("No daily or 1h candles available for high/low")
  [nil, nil]
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
  
  # Get current price and daily high/low
  current_price = candles_5m.last['close']
  daily_high, daily_low = get_daily_high_low
  
  # Count trend agreements
  uptrend_count = [trend_5m, trend_15m, trend_1h].count('uptrend')
  downtrend_count = [trend_5m, trend_15m, trend_1h].count('downtrend')
  total_agreements = uptrend_count + downtrend_count
  
  # Determine overall trend and confidence level
  trend = 'sideways'
  confidence = 'low'
  confidence_reason = ''
  timeframe_alignment = 'conflicting'
  
  if uptrend_count == 3 && rsi_5m < 70
    trend = 'uptrend'
    confidence = 'high'
    confidence_reason = 'All 3 timeframes agree on uptrend, RSI not overbought'
    timeframe_alignment = 'all_uptrend'
  elsif downtrend_count == 3 && rsi_5m > 30
    trend = 'downtrend'
    confidence = 'high'
    confidence_reason = 'All 3 timeframes agree on downtrend, RSI not oversold'
    timeframe_alignment = 'all_downtrend'
  elsif uptrend_count >= 2 && rsi_5m < 70
    trend = 'uptrend'
    confidence = 'medium'
    confidence_reason = "Majority (#{uptrend_count}/3) timeframes show uptrend, RSI not overbought"
    timeframe_alignment = 'majority_uptrend'
  elsif downtrend_count >= 2 && rsi_5m > 30
    trend = 'downtrend'
    confidence = 'medium'
    confidence_reason = "Majority (#{downtrend_count}/3) timeframes show downtrend, RSI not oversold"
    timeframe_alignment = 'majority_downtrend'
  else
    # Sideways or conflicting
    if total_agreements == 0
      confidence_reason = 'All timeframes show sideways movement'
    elsif uptrend_count >= 2 && rsi_5m >= 70
      confidence_reason = "Majority uptrend but RSI #{rsi_5m} >= 70 (overbought)"
    elsif downtrend_count >= 2 && rsi_5m <= 30
      confidence_reason = "Majority downtrend but RSI #{rsi_5m} <= 30 (oversold)"
    else
      confidence_reason = 'Conflicting timeframe signals'
    end
  end
  
  {
    trend: trend,
    confidence: confidence,
    confidence_reason: confidence_reason,
    rsi: rsi_5m,
    rsi_interpretation: rsi_5m < 30 ? 'oversold' : (rsi_5m > 70 ? 'overbought' : 'neutral'),
    timeframe_alignment: timeframe_alignment,
    timeframe_details: {
      '5m': trend_5m,
      '15m': trend_15m,
      '1h': trend_1h
    },
    current_price: current_price,
    daily_high: daily_high,
    daily_low: daily_low
  }
end

# Enhanced trading decision with comprehensive logging
def enhanced_trading_decision
  analysis = enhanced_trend_analysis
  
  # Log the enhanced analysis with detailed breakdown
  log("=== ENHANCED ANALYSIS ===")
  log("Trend: #{analysis[:trend]}")
  log("Confidence: #{analysis[:confidence].upcase} - #{analysis[:confidence_reason]}")
  log("RSI: #{analysis[:rsi]} (#{analysis[:rsi_interpretation]})")
  log("Timeframe Details: 5m: #{analysis[:timeframe_details][:'5m']}, 15m: #{analysis[:timeframe_details][:'15m']}, 1h: #{analysis[:timeframe_details][:'1h']}")
  log("Timeframe Alignment: #{analysis[:timeframe_alignment]}")
  log("Current Price: #{analysis[:current_price]}")
  log("Daily High: #{analysis[:daily_high] || 'N/A'}, Daily Low: #{analysis[:daily_low] || 'N/A'}")
  log("=========================")
  
  # Return trading decision
  case analysis[:trend]
  when 'uptrend'
    'ORDER_TYPE_BUY'
  when 'downtrend'
    'ORDER_TYPE_SELL'
  else
    # Sideways market: use RSI extremes for mean reversion
    if analysis[:rsi] < 30
      log("Sideways market: RSI #{analysis[:rsi]} indicates oversold, triggering BUY")
      'ORDER_TYPE_BUY'
    elsif analysis[:rsi] > 70
      log("Sideways market: RSI #{analysis[:rsi]} indicates overbought, triggering SELL")
      'ORDER_TYPE_SELL'
    else
      nil
    end
  end
end

# Performance tracking
$bad_trades_avoided = 0
$total_analysis_cycles = 0

# Main loop to check positions every 5 minutes and place a trade if necessary
loop do
  begin
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
          # EMERGENCY RSI BLOCK - Should never trade at extreme RSI levels
          if (enhanced_trade_type == 'ORDER_TYPE_BUY' && enhanced_analysis[:rsi] >= 65) || 
            (enhanced_trade_type == 'ORDER_TYPE_SELL' && enhanced_analysis[:rsi] <= 35)
            log("🚫 EMERGENCY RSI BLOCK: RSI #{enhanced_analysis[:rsi]} too extreme for #{enhanced_trade_type}")
          # DAILY HIGH FILTER - Prevent ceiling buying
          elsif enhanced_trade_type == 'ORDER_TYPE_BUY' && enhanced_analysis[:daily_high] && 
                enhanced_analysis[:current_price] >= enhanced_analysis[:daily_high] * 0.995
            log("🚫 DAILY HIGH BLOCK: Current price #{enhanced_analysis[:current_price]} too close to daily high #{enhanced_analysis[:daily_high]}")
          # DAILY LOW FILTER - Prevent floor selling
          elsif enhanced_trade_type == 'ORDER_TYPE_SELL' && enhanced_analysis[:daily_low] && 
                enhanced_analysis[:current_price] <= enhanced_analysis[:daily_low] * 1.005
            log("🚫 DAILY LOW BLOCK: Current price #{enhanced_analysis[:current_price]} too close to daily low #{enhanced_analysis[:daily_low]}")
          else
            place_trade(enhanced_trade_type, initial_lot_size.to_f, 1000, true)
          end
        else
          log("Enhanced analysis: No trade (low confidence)")
        end
      else
        # Use old system for trading (default - safe mode)
        if old_trade_type
          place_trade(old_trade_type, initial_lot_size.to_f, 1000, true)
        end
      end
    end
  rescue StandardError => e
    log("Error occurred: #{e.message}")
  end
  

  # Sleep for n seconds before checking positions again
  sleep(300)
end
