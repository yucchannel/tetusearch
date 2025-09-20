# route_search_top3_with_popular.rb
require 'open-uri'
require 'nokogiri'
require 'uri'

POPULAR_FILE = "popular_lines.txt"

# --- 人気路線ランキングのロード / 保存 ---
def load_popular_lines
  if File.exist?(POPULAR_FILE)
    lines = File.read(POPULAR_FILE).lines.map(&:chomp)
    lines.map { |l| k, v = l.split("||"); [k, v.to_i] }.to_h
  else
    Hash.new(0)
  end
end

def save_popular_lines(hash)
  File.open(POPULAR_FILE, "w") do |f|
    hash.each { |line, count| f.puts "#{line}||#{count}" }
  end
end

POPULAR_LINES = load_popular_lines

def count_line(line_name)
  POPULAR_LINES[line_name] += 1
  save_popular_lines(POPULAR_LINES)
end

# --- 入力 ---
print "出発駅 > "
from = gets.strip
print "到着駅 > "
to = gets.strip

url = "https://transit.yahoo.co.jp/search/result?from=#{URI.encode_www_form_component(from)}&to=#{URI.encode_www_form_component(to)}"

begin
  html = URI.open(url)
rescue OpenURI::HTTPError => e
  puts "Webページ取得エラー: #{e.message}"
  exit
end

doc = Nokogiri::HTML(html)
routes = doc.css(".routeDetail")
if routes.empty?
  puts "ルートが見つかりません。駅名・停留所名を確認してください。"
  exit
end

def clean_text(str)
  str.gsub(/時刻表.*|地図|出口/, '').strip
end

def print_route(route)
  times = route.css(".time").map(&:text)
  puts "出発: #{times.first} → 到着: #{times.last}" if times.any?

  # 鉄道区間
  route.css(".transport").each_with_index do |t, i|
    line_name = clean_text(t.css("div").text)
    count_line(line_name)  # 人気ランキングにカウント

    boarding  = clean_text(t.css(".station").first.text) rescue ""
    platform  = clean_text(t.css(".note").text) rescue ""
    delay     = t.css(".delay").text.strip rescue ""

    puts "  ■ 鉄道区間 #{i+1}: #{line_name}"
    puts "      乗車駅: #{boarding}" unless boarding.empty?
    puts "      のりば: #{platform}" unless platform.empty?
    puts "      ⚠ 遅延: \e[31m#{delay}\e[0m" unless delay.empty?

    next_station = route.css(".station")[i+1]
    puts "      降車駅: #{clean_text(next_station.text)}" if next_station
  end

  # バス区間
  route.css(".bus").each_with_index do |b, i|
    line_name = clean_text(b.css("div").text)
    count_line(line_name)  # 人気ランキングにカウント

    boarding  = clean_text(b.css(".station")[0].text) rescue ""
    next_station = b.css(".station")[1]
    puts "  ■ バス区間 #{i+1}: #{line_name}"
    puts "      乗車停留所: #{boarding}" unless boarding.empty?
    puts "      降車停留所: #{clean_text(next_station.text)}" if next_station
  end

  # 徒歩区間
  route.css(".walk").each_with_index do |w, i|
    info = clean_text(w.text)
    puts "  ■ 徒歩区間 #{i+1}: #{info}"
  end
  puts "-"*40
end

# --- 上位3ルートだけ表示 ---
puts "===== 上位3ルート候補 ====="
routes.first(3).each_with_index do |route, idx|
  puts "ルート候補 #{idx+1}"
  print_route(route)
end

# --- 遅延なし迂回ルート（上位3ルートのみ） ---
puts "===== 遅延なし迂回ルート（上位3） ====="
routes.first(3).each_with_index do |route, idx|
  delays = route.css(".transport .delay").map { |d| d.text.strip }
  next unless delays.all?(&:empty?)
  puts "ルート候補 #{idx+1}"
  print_route(route)
end

# --- 人気路線ランキング表示（上位10） ---
puts "===== 人気路線ランキング（上位10） ====="
POPULAR_LINES.sort_by { |line, count| -count }.first(10).each_with_index do |(line, count), idx|
  puts "#{idx+1}. #{line} （検索回数: #{count}）"
end
