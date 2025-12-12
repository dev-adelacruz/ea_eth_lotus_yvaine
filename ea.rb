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

# Function to log enhanced analysis results
def log_enhanced_analysis(analysis)
  log("=== ENHANCED ANALYSIS ===")
  log("Trend: #{analysis[:trend]}")
  log("Confidence: #{analysis[:confidence].upcase} - #{analysis[:confidence_reason]}")
  log("RSI: #{analysis[:rsi]} (#{analysis[:rsi_interpretation]})")
  log("Timeframe Details: 5m: #{analysis[:timeframe_details][:'5m']}, 15m: #{analysis[:timeframe_details][:'15m']}, 1h: #{analysis[:timeframe_details][:'1h']}")
  log("Timeframe Alignment: #{analysis[:timeframe_alignment]}")
  log("Current Price: #{analysis[:current_price]}")
  log("Daily High: #{analysis[:daily_high] || 'N/A'}, Daily Low: #{analysis[:daily_low] || 'N/A'}")
  log("=========================")
end

API_KEY = ENV['API_KEY']
ACCOUNT_ID = ENV['ACCOUNT_ID']
REGION_BASE_URL = ENV['REGION_BASE_URL']
REGION_MARKET_BASE_URL = ENV['REGION_MARKET_BASE_URL']
TAKE_PROFIT_BUFFER = ENV['TAKE_PROFIT_BUFFER']
INITIAL_LOT_SIZE = ENV['INITIAL_LOT_SIZE']
PAIR_SYMBOL = ENV['PAIR_SYMBOL'] || 'ETHUSDm'

# Enhanced configuration
ENABLE_ENHANCED_ANALYSIS = true  # Set to true to use enhanced analysis for trading

# Advanced filter configuration
ENABLE_CONSOLIDATION_FILTER = true      # Filter out trades during extreme consolidation
ENABLE_VOLATILITY_FILTER = true         # Adjust for high volatility whipsaws
ENABLE_4H_CONFIRMATION = false          # Require 4H timeframe alignment (default false per user request)
FILTER_AGGRESSIVENESS = "MEDIUM"        # LOW, MEDIUM, HIGH (trade frequency vs quality)

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

# Calculate Average True Range (ATR) for volatility measurement
def calculate_atr(candles, period=14)
  return nil if candles.nil? || candles.length < period + 1
  
  true_ranges = []
  (1...candles.length).each do |i|
    high = candles[i]['high'].to_f
    low = candles[i]['low'].to_f
    prev_close = candles[i-1]['close'].to_f
        
    tr1 = high - low
    tr2 = (high - prev_close).abs
    tr3 = (low - prev_close).abs
        
    true_ranges << [tr1, tr2, tr3].max
  end
  
  # Simple moving average of true ranges
  atr = true_ranges.last(period).sum / period.to_f
  atr.round(4)
end

# Calculate Bollinger Band width ratio (for consolidation detection)
def bollinger_band_width_ratio(candles, period=20, std_dev=2.0)
  return nil if candles.nil? || candles.length < period
  
  closes = candles.last(period).map { |c| c['close'].to_f }
  return nil if closes.empty?
  
  sma = closes.sum / closes.length.to_f
  variance = closes.map { |c| (c - sma) ** 2 }.sum / closes.length.to_f
  std = Math.sqrt(variance)
  
  upper_band = sma + (std_dev * std)
  lower_band = sma - (std_dev * std)
  band_width = upper_band - lower_band
  width_ratio = band_width / sma  # relative width as percentage of price
  
  width_ratio
end

# Check if market is in consolidation (low volatility, ranging)
def is_consolidating?(candles_5m, candles_1h)
  return false unless ENABLE_CONSOLIDATION_FILTER
  
  # Use 1h candles for broader consolidation detection
  return false if candles_1h.nil? || candles_1h.length < 20
  
  bb_width_ratio = bollinger_band_width_ratio(candles_1h, 20, 2.0)
  return false if bb_width_ratio.nil?
  
  # Determine threshold based on aggressiveness
  threshold = case FILTER_AGGRESSIVENESS
              when "LOW" then 0.0257   # 2.57% - filter extreme 20% consolidation (20th percentile)
              when "MEDIUM" then 0.0369 # 3.69% - filter tightest 40% (40th percentile)
              when "HIGH" then 0.0540   # 5.40% - filter tightest 60% (60th percentile)
              else 0.0369
              end
  
  # Low BB width indicates consolidation
  bb_width_ratio < threshold
end

# Check volatility conditions and adjust trend confidence
def volatility_adjusted_trend(trend, candles_5m, current_price)
  return trend unless ENABLE_VOLATILITY_FILTER
  
  atr = calculate_atr(candles_5m, 14)
  return trend if atr.nil?
  
  # Get recent candles for MA calculation
  return trend if candles_5m.length < 20
  short_ma = candles_5m.last(6).map{|c| c['close'].to_f}.sum / 6
  long_ma = candles_5m.last(20).map{|c| c['close'].to_f}.sum / 20
  
  # Determine if price is beyond MA by sufficient ATR multiple
  atr_multiplier = case FILTER_AGGRESSIVENESS
                   when "LOW" then 0.5
                   when "MEDIUM" then 1.0
                   when "HIGH" then 1.5
                   else 1.0
                   end
  
  required_distance = atr * atr_multiplier
  
  case trend
  when 'uptrend'
    # For uptrend, require price above MA by at least required_distance
    (current_price - short_ma) >= required_distance ? 'uptrend' : 'sideways'
  when 'downtrend'
    # For downtrend, require price below MA by at least required_distance
    (short_ma - current_price) >= required_distance ? 'downtrend' : 'sideways'
  else
    trend
  end
end

# Get 4H trend for higher timeframe confirmation
def get_4h_trend
  return 'sideways' unless ENABLE_4H_CONFIRMATION
  
  candles_4h = get_candles('4h')
  return 'sideways' if candles_4h.nil? || candles_4h.empty?
  
  calculate_trend(candles_4h, '4h')
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
    "comment" => "LOTUS YVAINE BETA 0.0.3"
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
  tp_buffer = (TAKE_PROFIT_BUFFER || 2).to_f
  trade_type == 'POSITION_TYPE_BUY' ? tp_buffer : (0 - tp_buffer)
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
def calculate_trend(candles, timeframe='5m')
  return 'sideways' if candles.nil? || candles.empty?
  
  # Define timeframe-specific parameters
  case timeframe
  when '5m'
    short_period = 12    # 1 hour of data (12 * 5m)
    long_period = 72     # 6 hours of data (72 * 5m)
  when '15m'
    short_period = 8     # 2 hours of data (8 * 15m)
    long_period = 32     # 8 hours of data (32 * 15m)
  when '1h'
    short_period = 20    # 20 hours ≈ 1 trading day
    long_period = 50     # 50 hours ≈ 2 trading days
  when '4h'
    short_period = 10    # 40 hours ≈ 1.7 days
    long_period = 30     # 120 hours ≈ 5 days
  else
    # Default to original values for unknown timeframes
    short_period = 6
    long_period = 60
  end
  
  # Ensure we have enough data
  return 'sideways' if candles.length < long_period
  
  short_ma = candles.last(short_period).map{|candle| candle['close'].to_f}.sum / short_period
  long_ma = candles.last(long_period).map{|candle| candle['close'].to_f}.sum / long_period
  
  if short_ma > long_ma
    'uptrend'
  elsif short_ma < long_ma
    'downtrend'
  else
    'sideways'
  end
end

# Function to get daily high and low prices
def get_daily_high_low(candles_1h_param = nil)
  # Use provided 1h candles or fetch them
  candles_1h = candles_1h_param || get_candles('1h')
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
  trend_5m = calculate_trend(candles_5m, '5m')
  trend_15m = calculate_trend(candles_15m, '15m')
  trend_1h = calculate_trend(candles_1h, '1h')
  
  # Calculate RSI for 5m (entry timeframe)
  prices_5m = candles_5m.map { |c| c['close'] }
  rsi_5m = calculate_rsi(prices_5m)
  
  # Get current price and daily high/low
  current_price = candles_5m.last['close']
  daily_high, daily_low = get_daily_high_low(candles_1h)
  
  # Count trend agreements
  uptrend_count = [trend_5m, trend_15m, trend_1h].count('uptrend')
  downtrend_count = [trend_5m, trend_15m, trend_1h].count('downtrend')
  total_agreements = uptrend_count + downtrend_count
  
  # Determine timeframe alignment (based ONLY on timeframe agreement)
  timeframe_alignment = if uptrend_count == 3
    'all_uptrend'
  elsif downtrend_count == 3
    'all_downtrend'
  elsif uptrend_count >= 2
    'majority_uptrend'
  elsif downtrend_count >= 2
    'majority_downtrend'
  else
    'conflicting'
  end
  
  # Determine overall trend and confidence level
  trend = 'sideways'
  confidence = 'low'
  confidence_reason = ''
  
  if uptrend_count == 3 && rsi_5m < 70
    trend = 'uptrend'
    confidence = 'high'
    confidence_reason = 'All 3 timeframes agree on uptrend, RSI not overbought'
  elsif downtrend_count == 3 && rsi_5m > 30
    trend = 'downtrend'
    confidence = 'high'
    confidence_reason = 'All 3 timeframes agree on downtrend, RSI not oversold'
  else
    # Sideways or conflicting
    if total_agreements == 0
      confidence_reason = 'All timeframes show sideways movement'
    elsif uptrend_count >= 2 && rsi_5m >= 70
      confidence_reason = "Majority uptrend but RSI #{rsi_5m} >= 70 (overbought)"
    elsif downtrend_count >= 2 && rsi_5m <= 30
      confidence_reason = "Majority downtrend but RSI #{rsi_5m} <= 30 (oversold)"
    else
      confidence_reason = 'Conflicting timeframe signals (require all 3 timeframes aligned)'
    end
  end

  # Apply advanced filters
  original_trend = trend
  original_confidence = confidence

  # 1. Consolidation filter
  if ENABLE_CONSOLIDATION_FILTER && is_consolidating?(candles_5m, candles_1h)
    trend = 'sideways'
    confidence = 'low'
    confidence_reason = 'Market in consolidation - avoiding trade'
    log("CONSOLIDATION FILTER: Market is ranging, avoiding trade")
  end

  # 2. Volatility filter (adjust trend if too volatile)
  if ENABLE_VOLATILITY_FILTER && (trend == 'uptrend' || trend == 'downtrend')
    adjusted_trend = volatility_adjusted_trend(trend, candles_5m, current_price)
    if adjusted_trend != trend
      trend = adjusted_trend
      confidence = 'low'
      confidence_reason = 'Volatility too high for clear trend'
      log("VOLATILITY FILTER: Trend adjusted due to high volatility")
    end
  end

  # 3. 4H timeframe confirmation
  if ENABLE_4H_CONFIRMATION && (trend == 'uptrend' || trend == 'downtrend')
    trend_4h = get_4h_trend
    if trend_4h != 'sideways' && trend_4h != trend
      # 4H trend contradicts our trend
      trend = 'sideways'
      confidence = 'low'
      confidence_reason = "4H trend (#{trend_4h}) contradicts lower timeframe trend"
      log("4H CONFIRMATION FILTER: 4H trend #{trend_4h} contradicts, avoiding trade")
    elsif trend_4h == trend
      # 4H confirms, increase confidence
      confidence = 'high' if confidence == 'medium'
      confidence_reason = "#{confidence_reason} (confirmed by 4H)"
    end
  end

  # Log filter application if any
  if original_trend != trend || original_confidence != confidence
    log("FILTERS APPLIED: Trend changed from #{original_trend} (#{original_confidence}) to #{trend} (#{confidence})")
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

# Calculate dynamic lot multiplier based on analysis confidence and conditions
def lot_multiplier(analysis)
  # Base multiplier for high confidence trades (all 3 timeframes aligned)
  base_multiplier = 2.0
  
  # RSI bonus: optimal range 40-60 gets bonus
  rsi_bonus = 0.0
  if analysis[:rsi] >= 40 && analysis[:rsi] <= 60
    rsi_bonus = 0.5
  end
  
  # Filter bonus: each enabled filter that passed adds 0.15
  filter_bonus = 0.0
  enabled_filters = 0
  passed_filters = 0
  
  # Check consolidation filter
  if ENABLE_CONSOLIDATION_FILTER
    enabled_filters += 1
    # If we have a high confidence trade, consolidation filter must have passed
    passed_filters += 1 if analysis[:confidence] == 'high'
  end
  
  # Check volatility filter  
  if ENABLE_VOLATILITY_FILTER
    enabled_filters += 1
    # If we have a high confidence trade, volatility filter must have passed
    passed_filters += 1 if analysis[:confidence] == 'high'
  end
  
  # Calculate filter bonus (0.15 per passed filter)
  filter_bonus = passed_filters * 0.15
  
  # 4H confirmation bonus (if enabled and aligned)
  four_hour_bonus = 0.0
  if ENABLE_4H_CONFIRMATION && analysis[:confidence] == 'high'
    # If 4H confirmation is enabled and we have high confidence, 4H must be aligned
    four_hour_bonus = 0.5
  end
  
  # Aggressiveness multiplier
  aggressiveness_multiplier = case FILTER_AGGRESSIVENESS
                              when "LOW" then 1.0
                              when "MEDIUM" then 1.1
                              when "HIGH" then 1.2
                              else 1.0
                              end
  
  # Calculate total multiplier
  total_multiplier = (base_multiplier + rsi_bonus + filter_bonus + four_hour_bonus) * aggressiveness_multiplier
  
  # Cap at maximum 3.0
  total_multiplier = [total_multiplier, 3.0].min
  
  # Never go below 0.5
  total_multiplier = [total_multiplier, 0.5].max
  
  log("LOT MULTIPLIER CALCULATION:")
  log("  Base: #{base_multiplier}")
  log("  RSI bonus (#{analysis[:rsi]}): #{rsi_bonus}")
  log("  Filter bonus (#{passed_filters}/#{enabled_filters} passed): #{filter_bonus}")
  log("  4H bonus: #{four_hour_bonus}")
  log("  Aggressiveness (#{FILTER_AGGRESSIVENESS}): #{aggressiveness_multiplier}")
  log("  Total multiplier: #{total_multiplier.round(2)}")
  
  total_multiplier.round(2)
end

# Enhanced trading decision with comprehensive logging and dynamic lot sizing
def enhanced_trading_decision(analysis = nil)
  # Use provided analysis or compute it
  analysis = analysis || enhanced_trend_analysis
  
  # Return trading decision with dynamic lot multiplier
  case analysis[:trend]
  when 'uptrend'
    if analysis[:confidence] == 'high'
      multiplier = lot_multiplier(analysis)
      return { trade_type: 'ORDER_TYPE_BUY', multiplier: multiplier }
    else
      # No trade if not high confidence
      return nil
    end
  when 'downtrend'
    if analysis[:confidence] == 'high'
      multiplier = lot_multiplier(analysis)
      return { trade_type: 'ORDER_TYPE_SELL', multiplier: multiplier }
    else
      # No trade if not high confidence
      return nil
    end
  else
    # Sideways market: NO TRADE (eliminated per user request)
    log("Sideways market: No trade (RSI-based trades eliminated)")
    return nil
  end
end


# Main loop to check positions every 5 minutes and place a trade if necessary
  loop do
    begin
      positions = get_positions
      # If positions is nil (API error), skip this cycle
      if positions.nil?
        log("Skipping cycle due to API error in get_positions")
        sleep(300)
        next
      end
    
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
      # Run enhanced analysis for trading decision (once per cycle)
      enhanced_analysis = enhanced_trend_analysis
      # Log the analysis once
      log_enhanced_analysis(enhanced_analysis)
      
      decision = enhanced_trading_decision(enhanced_analysis)
      
      log("========================")

      # Use enhanced analysis for trading
      if decision && decision[:trade_type]
        trade_type = decision[:trade_type]
        multiplier = decision[:multiplier]
        # EMERGENCY RSI BLOCK - Should never trade at extreme RSI levels
        if (trade_type == 'ORDER_TYPE_BUY' && enhanced_analysis[:rsi] >= 65) || 
          (trade_type == 'ORDER_TYPE_SELL' && enhanced_analysis[:rsi] <= 35)
          log("🚫 EMERGENCY RSI BLOCK: RSI #{enhanced_analysis[:rsi]} too extreme for #{trade_type}")
        else
          dynamic_lot_size = initial_lot_size.to_f * multiplier
          place_trade(trade_type, dynamic_lot_size, 1000, true)
        end
      else
        log("Enhanced analysis: No trade (low confidence)")
      end
    end
  rescue StandardError => e
    log("Error occurred: #{e.message}")
    log("Backtrace (first 10): #{e.backtrace.first(10).join("\n")}")
  end
  

  # Sleep for n seconds before checking positions again
  sleep(300)
end
