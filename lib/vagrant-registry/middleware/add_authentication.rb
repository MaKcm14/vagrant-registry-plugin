require "cgi"
require "json"
require "net/http"
require "uri"

require_relative "../client"

# Based on VagrantPlugins::LoginCommand::AddAuthentication

module VagrantPlugins
  module Registry
    class AddAuthentication

      def initialize(app, env)
        @app = app
        @logger = Log4r::Logger.new("vagrant::registry::add_authentication")
      end

      # TODO: refactor it!
      def get_repo_name(url)
        url.path.split('/').each_with_index do |url_item, idx|
          if url_item == "boxes"
            return url.path.split('/')[idx+1, 2].join('/')
          end
        end
        url.path.split('/')[1..3].join('/')
      end

      def get_user_boxes_list(url)
        url_copy = url.dup
        url_copy.path = "/api/v1/boxes/" + get_repo_name(url_copy).split('/')[0]
        resp = Net::HTTP.get_response(url_copy)

        if resp.is_a?(Net::HTTPRedirection)
          url_copy.path = resp['location']
          resp = Net::HTTP.get_response(url_copy)
        end

        resp.body
      end

      def add_token?(url)
        if url.host == "vagrantcloud.com"
          return true
        end

        body = JSON.parse(get_user_boxes_list(url))
        repo_name = get_repo_name(url)

        body["results"].each do |box|
          if box['tag'] == repo_name
            return false
          end
        end

        return true
      end

      def call(env)
        tokens = Client.new(env[:env], nil).all_tokens

        @logger.info("\n\n\n==> VAGRANT-REGISTRY \n\n\n")
        @logger.info("==> tokens: #{tokens}")

        unless tokens.empty?
          env[:box_urls].map! do |url|
            @logger.info("==> url: #{url}")

            u = URI.parse(url)
            @logger.info("==> u: #{u}")

            if (ARGV[0] == "box" || ARGV[0] == "init") && !add_token?(u)
              next u.to_s
            end

            token = tokens[u.host]
  
            @logger.info("==> token: #{token}")

            unless token.nil?
              q = CGI.parse(u.query || "")

              @logger.info("==> q: #{q}")

              current = q["auth_token"]
              if current && current.empty?
                q["auth_token"] = token
              end

              u.query = URI.encode_www_form(q)

              @logger.info("==> u: #{u}")
            end

            u.to_s
          end
        end

        @app.call(env)
      end
    end
  end
end
