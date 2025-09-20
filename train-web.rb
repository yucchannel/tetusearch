# app.rb
require 'sinatra'
require 'open-uri'
require 'nokogiri'
require 'uri'
require 'erb'

set :bind, '0.0.0.0'
set :port, 4567

# 人気路線ランキング用ファイル
POPULAR_FILE = "popular_lines.txt"

# ファイルからロード
def load_popular_lines
  if File.exist?(POPULAR_FILE)
    lines = File.read(POPULAR_FILE).lines.map(&:chomp)
    lines.map { |l| k, v = l.split("||"); [k, v.to_i] }.to_h
  else
    Hash.new(0)
  end
end

# ファイルに保存
def save_popular_lines(hash)
  File.open(POPULAR_FILE, "w") do |f|
    hash.each { |line, count| f.puts "#{line}||#{count}" }
  end
end

# 初期ロード
POPULAR_LINES = load_popular_lines

helpers do
  def clean_text(str)
    str.gsub(/時刻表.*|地図|出口/, '').strip
  end

  # テキスト保存用に路線名をカウント
  def count_line(line_name)
    POPULAR_LINES[line_name] += 1
    save_popular_lines(POPULAR_LINES)
  end

  # Yahoo!路線検索のページ解析
  def parse_routes(doc)
    routes = doc.css(".routeDetail")
    result = []

    routes.first(3).each_with_index do |route, idx|
      r = {times: route.css(".time").map(&:text), sections: []}

      # 鉄道区間
      route.css(".transport").each_with_index do |t, i|
        boarding  = clean_text(t.css(".station").first.text) rescue ""
        platform  = clean_text(t.css(".note").text) rescue ""
        delay     = t.css(".delay").text.strip rescue ""
        next_station = route.css(".station")[i+1]
        dropoff = next_station ? clean_text(next_station.text) : ""

        line_name = clean_text(t.css("div").text)
        count_line(line_name)  # 人気ランキング用にカウント

        r[:sections] << {
          type: "鉄道",
          line: line_name,
          boarding: boarding,
          dropoff: dropoff,
          platform: platform,
          delay: delay
        }
      end

      # バス区間
      route.css(".bus").each_with_index do |b, i|
        boarding  = clean_text(b.css(".station")[0].text) rescue ""
        next_station = b.css(".station")[1]
        dropoff = next_station ? clean_text(next_station.text) : ""
        line_name = clean_text(b.css("div").text)
        count_line(line_name)  # 人気ランキング用にカウント

        r[:sections] << {
          type: "バス",
          line: line_name,
          boarding: boarding,
          dropoff: dropoff
        }
      end

      # 徒歩区間
      route.css(".walk").each do |w|
        r[:sections] << {
          type: "徒歩",
          info: clean_text(w.text)
        }
      end

      result << r
    end
    result
  end
end

# 検索フォーム
get '/' do
  erb :index
end

# 検索結果
post '/search' do
  from = params[:from]
  to   = params[:to]
  url = "https://transit.yahoo.co.jp/search/result?from=#{URI.encode_www_form_component(from)}&to=#{URI.encode_www_form_component(to)}"

  begin
    html = URI.open(url)
  rescue
    return "検索中にエラーが発生しました"
  end

  doc = Nokogiri::HTML(html)
  @routes = parse_routes(doc)
  erb :results
end

# 人気路線ランキング表示
get '/popular' do
  # 利用回数順にソートして上位10路線を取得
  @ranking = POPULAR_LINES.sort_by { |line, count| -count }.first(10)
  erb :popular
end
