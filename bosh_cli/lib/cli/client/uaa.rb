require 'uaa'
require 'uri'

module Bosh
  module Cli
    module Client
      class Uaa
        def initialize(options, ssl_ca_file)
          url = options.fetch('url')
          unless URI.parse(url).instance_of?(URI::HTTPS)
            err('Failed to connect to UAA, HTTPS protocol is required')
          end
          @ssl_ca_file = ssl_ca_file

          client = ENV['BOSH_CLIENT'] || 'bosh_cli'
          client_secret = ENV['BOSH_CLIENT_SECRET'] || nil

          @token_issuer = CF::UAA::TokenIssuer.new(url, client, client_secret, { ssl_ca_file: ssl_ca_file })
        end

        def prompts
          @token_issuer.prompts.map do |field, (type, display_text)|
            Prompt.new(field, type, display_text)
          end
        rescue CF::UAA::SSLException => e
          raise e unless @ssl_ca_file.nil?
          err('Invalid SSL Cert. Use --ca-cert to specify SSL certificate')
        end

        def login(credentials)
          credentials = credentials.select { |_, c| !c.empty? }
          token = @token_issuer.owner_password_credentials_grant(credentials)
          if token
            decoded = CF::UAA::TokenCoder.decode(
              token.info['access_token'],
              { verify: false }, # token signature not verified because CLI doesn't have the secret key
              nil, nil)
            full_token = "#{token.info['token_type']} #{token.info['access_token']}"
            { username: decoded['user_name'], token: full_token }
          end
        rescue CF::UAA::TargetError => e
          err("Failed to login: #{e.info['error_description']}")
        rescue CF::UAA::BadResponse
          nil
        end

        class Prompt < Struct.new(:field, :type, :display_text)
          def password?
            type == 'password'
          end
        end
      end
    end
  end
end