#!/usr/bin/env ruby
# Encoding: utf-8
#
# Original sample code is here.
# https://developers.google.com/adwords/api/docs/samples/python/optimization?hl=ja#estimate-keyword-traffic

require 'adwords_api'
require 'pp'
require 'csv'

def estimate_keyword_traffic(values)
  adwords = AdwordsApi::Api.new

  # TrafficEstimatorServiceの利用
  # https://developers.google.com/adwords/api/docs/guides/traffic-estimator-service?hl=ja
  traffic_estimator_srv = adwords.service(:TrafficEstimatorService, API_VERSION)

  # 1リクエスト当り最大2000単語まで利用可能
  # keywords = [
  #             # xsi_type: リクエストに必須な項目. 作成するオブジェクトのタイプを指定する
  #             # text: 見積もり対象のキーワード
  #             # match_type: キーワードのマッチタイプ
  #             {:xsi_type => 'Keyword', :text => '出会い', :match_type => 'BROAD'},
  #             {:xsi_type => 'Keyword', :text => '出会い', :match_type => 'PHRASE'},
  #             {:xsi_type => 'Keyword', :text => '出会い', :match_type => 'EXACT'}
  #            ]
  keyword_hash = {}
  keywords = []
  values.each_with_index {|value, i|
    if keyword_hash.key?(value[:keyword] + value[:match_type].upcase)
      keyword_hash[value[:keyword] + value[:match_type].upcase].push(i)
    else
      keywords.push({:xsi_type => 'Keyword', :text => value[:keyword], :match_type => value[:match_type].upcase})
      keyword_hash[value[:keyword] + value[:match_type].upcase] = [i]
    end
  }

  # リクエスト用に整形
  keyword_requests = keywords.map {|keyword| {:keyword => keyword}}
  # pp keyword_requests

  # ネガティブな単語はフィルタリングする機能がついている（必要ないのでコメントアウト）
  # keyword_requests[3][:is_negative] = true

  # adgroup用の推定リクエスト作成
  ad_group_request = {
      :keyword_estimate_requests => keyword_requests,
      :max_cpc => {
          :micro_amount => 1000000 # 最低1円以上入札
      }
  }

  # campaign用の推定リクエスト作成
  campaign_request = {
    :ad_group_estimate_requests => [ad_group_request]
    # 推定時に地域が設定できる（必要ないのでコメントアウト）
    # :criteria => [
    #       {:xsi_type => 'Location', :id => 2840}, # United States
    #       {:xsi_type => 'Language', :id => 1000}  # English
    #   ]
  }

  # セレクター作成
  selector = {
    :campaign_estimate_requests => [campaign_request],
    # デバイス別に単位で推定するか設定できる（Desktop, Mobile, Tablet）
    :platform_estimate_requested => true
  }
  # pp selector

  # Execute the request.
  res = traffic_estimator_srv.get(selector)
  # pp res

  # Display traffic estimates.
  if res and res[:campaign_estimates] and
      res[:campaign_estimates].size > 0
    campaign_estimate = res[:campaign_estimates].first

    # unless campaign_estimate[:platform_estimates].nil?
    #   # キャンペーン単位の推定値（デバイス別）
    #   campaign_estimate[:platform_estimates].each do |platform_estimate|
    #     platform_message = ('Results for the platform with ID %d and name ' +
    #         '"%s":') % [platform_estimate[:platform][:id],
    #         platform_estimate[:platform][:platform_name]]
    #     display_mean_estimates(
    #         platform_message,
    #         platform_estimate[:min_estimate],
    #         platform_estimate[:max_estimate]
    #     )
    #   end
    # end

    # キーワード単位の推定値
    keyword_estimates =
        campaign_estimate[:ad_group_estimates].first[:keyword_estimates]
    keyword_estimates.each_with_index do |keyword_estimate, index|
      k = keyword_requests[index][:keyword]
      keyword_hash[k[:text] + k[:match_type]].each{|v_index|
        display_values(keyword_estimate, values[v_index])
      }
    end
  else
    puts 'No traffic estimates were returned.'
  end
end

def display_header(input)
  output = ['Est Min CPC', 'Est Max CPC',
            'Est Min Pos', 'Est Max Pos',
            'Est Min Click', 'Est Max Click',
            'Est Min Cost', 'Est Max Cost',
            'Est Min Imp', 'Est Max Imp'
           ]
  puts (input + output).join(',')
end

def display_values(estimate, input)
  values = input.to_a

  if estimate[:min][:average_cpc].nil? || estimate[:max][:average_cpc].nil?
    values += ['none1', 'none1']
  else
    if estimate[:min][:average_cpc][:micro_amount].nil? || estimate[:max][:average_cpc][:micro_amount].nil?
      values += ['none2', 'none2']
    else
      values += [format(estimate[:min][:average_cpc][:micro_amount]), format(estimate[:max][:average_cpc][:micro_amount])]
    end
  end

  values += [format(estimate[:min][:average_position]), format(estimate[:max][:average_position])]
  values += [format(estimate[:min][:clicks_per_day]), format(estimate[:max][:clicks_per_day])]

  if estimate[:min][:total_cost].nil? || estimate[:max][:total_cost].nil?
    values += ['none1', 'none1']
  else
    if estimate[:min][:total_cost][:micro_amount].nil? || estimate[:max][:total_cost][:micro_amount].nil?
      values += ['none2', 'none2']
    else
      values += [format(estimate[:min][:total_cost][:micro_amount]), format(estimate[:max][:total_cost][:micro_amount])]
    end
  end

  values += [format(estimate[:min][:impressions_per_day]), format(estimate[:max][:impressions_per_day])]
  puts values.join(',')
end

def format(value)
  return "nil" if value.nil?
  return "%.2f" % (value.to_f / 1000000)
end

def calculate_mean(min_money, max_money)
  return nil if min_money.nil? || max_money.nil?
  return (min_money.to_f + max_money.to_f) / 2.0
end

if __FILE__ == $0
  API_VERSION = :v201806
  CSV_FILE = ARGV[0]

  report = CSV.table(CSV_FILE)
  # ユニークなcampaign_id単位にcsvをまとめる
  report_by_camp = report.group_by{|i| i[:campaign_id]}
  STDERR.puts report_by_camp.keys.length

  begin
    display_header(report.headers)
    report_by_camp.each_with_index{|(camp_id, values), i|
      STDERR.puts i, camp_id
      estimate_keyword_traffic(values)
    }

  # Authorization error.
  rescue AdsCommon::Errors::OAuth2VerificationRequired => e
    puts "Authorization credentials are not valid. Edit adwords_api.yml for " +
        "OAuth2 client ID and secret and run misc/setup_oauth2.rb example " +
        "to retrieve and store OAuth2 tokens."
    puts "See this wiki page for more details:\n\n  " +
        'https://github.com/googleads/google-api-ads-ruby/wiki/OAuth2'

  # HTTP errors.
  rescue AdsCommon::Errors::HttpError => e
    puts "HTTP Error: %s" % e

  # API errors.
  rescue AdwordsApi::Errors::ApiException => e
    puts "Message: %s" % e.message
    puts 'Errors:'
    e.errors.each_with_index do |error, index|
      puts "\tError [%d]:" % (index + 1)
      error.each do |field, value|
        puts "\t\t%s: %s" % [field, value]
      end
    end
  end
end
