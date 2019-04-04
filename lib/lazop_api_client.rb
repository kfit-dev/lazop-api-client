#!/usr/bin/ruby
# -*- coding: UTF-8 -*-

require "lazop_api_client/version"

require 'rest-client'
require 'json'
require 'openssl'
require 'cgi'
require 'logger'
require 'socket'

$dir = ENV['HOME'] + '/logs/';
if !File.directory?($dir)
    Dir.mkdir $dir
end
$logger = Logger.new($dir + 'lazopsdk.log.' + Time.now.strftime('%Y-%m-%d'))
$logger.level = Logger::WARN
$logger.formatter = proc { |severity, datetime, progname, msg|
  "#{severity}: #{datetime}: #{msg}\n"
}

module LazopApiClient

    class UrlConstants
        Api_gateway_url_sg = 'https://api.lazada.sg/rest'
        Api_gateway_url_my = 'https://api.lazada.com.my/rest'
        Api_gateway_url_vn = 'https://api.lazada.vn/rest'
        Api_gateway_url_th = 'https://api.lazada.co.th/rest'
        Api_gateway_url_ph = 'https://api.lazada.com.ph/rest'
        Api_gateway_url_id = 'https://api.lazada.co.id/rest'
        Api_authorization_url = 'https://auth.lazada.com/rest'
    end

    class Constants
        Log_level_debug = 'DEBUG'
        Log_level_info = 'INFO'
        Log_level_error = 'ERROR'
    end

    class Client

        @serverUrl = nil
        @appkey = nil
        @appSecret = nil
        @logLevel = Constants::Log_level_error

        def initialize(serverUrl,appkey,appSecret)
            @serverUrl,@appkey,@appSecret = serverUrl,appkey,appSecret
        end

        def execute(request,accessToken = nil)

            sys_params = Hash.new
            sys_params[:app_key] = @appkey
            sys_params[:partner_id] = 'lazop-sdk-ruby-20180426'

            timestamp = request.timestamp
            if timestamp == nil
                timestamp = (Time.now.to_f * 1000).to_i
            end
            sys_params[:timestamp] = timestamp

            sys_params[:sign_method] = 'sha256'

            if @logLevel == Constants::Log_level_debug
                sys_params[:debug] = 'true'
            end

            if accessToken != nil
                sys_params[:access_token] = accessToken
            end

            sys_params[:sign] = sign_api_request(sys_params,request.api_params,request.api_name)

            rpcUrl = get_rest_url(@serverUrl,request.api_name)
            fullUrl = get_full_url(rpcUrl,sys_params)

            obj = nil
            begin
                if request.file_params.size() > 0 || request.http_method == 'POST'
                    obj = perform_post(fullUrl,request.api_params,request.file_params,request.header_params)
                else
                    obj = perform_get(fullUrl,request.api_params,request.header_params)
                end
            rescue Exception => e
                logApiError(fullUrl, "HTTP_ERROR", e.message)
                raise
            end

            if obj['code'] != nil and obj['code'] != '0'
                logApiError(fullUrl, obj['code'], obj['message'])
            else
                if @logLevel == Constants::Log_level_debug or @logLevel == Constants::Log_level_info
                    logApiError(fullUrl, '', '')
                end
            end

            return LazopApiClient::Response.new(obj['type'],obj['code'],obj['message'],obj['request_id'],obj)
        end

        def perform_get url,api_params,header_params

            param_str = ''

            if api_params != nil
                api_params.each do |k,v|
                    param_str += '&'
                    param_str += k.to_s()
                    param_str += '='
                    param_str += CGI.escape(v.to_s())
                end
            end

            res = JSON.parse(RestClient.get(url + param_str, header_params))

            return res

        end

        def setLogLevel(level)
            @logLevel = level
        end

        def url_encode(str)
          return str.gsub!(/[^-_.!~*'()a-zA-Z\d;\/?:@&=+$,\[\]]/n) { |x| x = format("%%%x", x[0])}
        end

        def logApiError requestUrl, code, message
            $logger.error '^_^' + requestUrl + '^_^' + code + '^_^' + message
        end

        def perform_post url, api_params,file_params,header_params

            all_params = api_params

            if file_params != nil
                file_params.each do |k,v|
                    all_params[k] = File.open(v, "rb")
                end
            end

            res = JSON.parse(RestClient.post(url,all_params))
            return res
        end

        def sign_api_request(sys_params,api_params,api_name)
            sort_arrays = nil

            if api_params != nil
                sort_arrays = sys_params.merge(api_params).sort_by do |k,v|
                    k.to_s()
                end
            else
                sort_arrays = sys_params.sort_by do |k,v|
                    k
                end
            end

            sign_str = ''
            sign_str += api_name
            sort_arrays.each do |k,v|
                sign_str += k.to_s()
                sign_str += v.to_s()
            end

            return OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), @appSecret, sign_str).upcase
        end

        def get_rest_url(url,api_name)
            length = url.length()
            if url[length -1] == '/'
            return url + api_name.index('/');
            end

            return url + api_name;
        end

        def get_full_url(url,params)

            full_url = url
            param_str = ''

            params.each do |k,v|
                if param_str.length() > 0
                    param_str += '&'
                end
                param_str += k.to_s()
                param_str += '='
                param_str += v.to_s()
            end

            full_url += '?'
            full_url += param_str

            return full_url
        end
    end

    class Request
        # this hash will hold all api params
        @api_params = nil
        # this hash will hold http header params
        @header_params = nil
        # this hash will hold byte arrays params , such as file path
        @file_params = nil

        @api_name = nil
        @http_method = 'POST'
        @timestamp = nil

        def initialize(api_name = nil,http_method = 'POST')
            @api_name , @http_method = api_name,http_method
            @api_params = Hash.new
            @header_params = Hash.new
            @file_params = Hash.new
        end

        def add_api_parameter(key,value)
            if key.kind_of? String
                @api_params[key] = value
            else
                raise 'api param key is not String'
            end
        end

        def add_http_parameter(key,value)
            if key.kind_of? String
                @header_params[key] = value
            else
                raise 'http param key is not String'
            end
        end

        # file_path must be String
        def add_file_parameter(key,file_path)
            if (key.kind_of? String) && (file_path.kind_of? String)
                @file_params[key] = file_path
            else
                raise 'http param key is not String'
            end
        end

        def timestamp
            @timestamp
        end

        def set_timestamp=(value)
            @timestamp = value
        end

        def api_params
            @api_params
        end

        def api_name
            @api_name
        end

        def http_method
            @http_method
        end

        def file_params
            @file_params
        end

        def header_params
            @header_params
        end
    end

    class Response

        def initialize(type,code,message,r_id,body)
            @type = type
            @code = code
            @message = message
            @body = body
            @request_id = r_id
        end

        def type
            # response type nil,ISP,ISV,SYSTEM
            # nil ：no error
            # ISP : API Service Provider Error
            # ISV : API Request Client Error
            # SYSTEM : Lazop platform Error
            @type
        end

        def code
            # response code, 0 is no error
            @code
        end

        def message
            @message
        end

        def body
            # http response body, contains all fileds
            @body
        end

        def request_id
            # api uniqe request id
            @request_id
        end

        def success?
            @code == '0'
        end
    end
end
