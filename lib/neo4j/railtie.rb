require 'active_support/notifications'
require 'rails/railtie'

module Neo4j
  class Railtie < ::Rails::Railtie
    config.neo4j = ActiveSupport::OrderedOptions.new

    # Add ActiveModel translations to the I18n load_path
    initializer 'i18n' do
      config.i18n.load_path += Dir[File.join(File.dirname(__FILE__), '..', '..', '..', 'config', 'locales', '*.{rb,yml}')]
    end

    rake_tasks do
      load 'neo4j/tasks/neo4j_server.rake'
      load 'neo4j/tasks/migration.rake'
    end

    class << self
      def java_platform?
        RUBY_PLATFORM =~ /java/
      end

      def setup_default_session(cfg)
        cfg.session_type ||= :server_db
        cfg.session_path ||= 'http://localhost:7474'
        cfg.session_options ||= {}
        cfg.sessions ||= []

        unless (uri = URI(cfg.session_path)).user.blank?
          cfg.session_options.reverse_merge!(basic_auth: {username: uri.user, password: uri.password})
          cfg.session_path = cfg.session_path.gsub("#{uri.user}:#{uri.password}@", '')
        end

        return if !cfg.sessions.empty?

        cfg.sessions << {type: cfg.session_type, path: cfg.session_path, options: cfg.session_options}
      end


      def start_embedded_session(session)
        # See https://github.com/jruby/jruby/wiki/UnlimitedStrengthCrypto
        security_class = java.lang.Class.for_name('javax.crypto.JceSecurity')
        restricted_field = security_class.get_declared_field('isRestricted')
        restricted_field.accessible = true
        restricted_field.set nil, false
        session.start
      end

      def open_neo4j_session(options)
        type, name, default, path = options.values_at(:type, :name, :default, :path)

        if !java_platform? && type == :embedded_db
          fail "Tried to start embedded Neo4j db without using JRuby (got #{RUBY_PLATFORM}), please run `rvm jruby`"
        end

        session = if options.key?(:name)
                    Neo4j::Session.open_named(type, name, default, path)
                  else
                    Neo4j::Session.open(type, path, options[:options])
                  end

        start_embedded_session(session) if type == :embedded_db
      end
    end

    # Starting Neo after :load_config_initializers allows apps to
    # register migrations in config/initializers
    initializer 'neo4j.start', after: :load_config_initializers do |app|
      cfg = app.config.neo4j
      # Set Rails specific defaults
      Neo4j::Railtie.setup_default_session(cfg)

      cfg.sessions.each do |session_opts|
        Neo4j::Railtie.open_neo4j_session(session_opts)
      end
      Neo4j::Config.configuration.merge!(cfg.to_hash)

      clear = "\e[0m"
      yellow = "\e[33m"
      cyan = "\e[36m"

      ActiveSupport::Notifications.subscribe('neo4j.cypher_query') do |_, start, finish, _id, payload|
        ms = (finish - start) * 1000
        Rails.logger.info " #{cyan}#{payload[:context]}#{clear} #{yellow}#{ms.round}ms#{clear} #{payload[:cypher]}" + (payload[:params].size > 0 ? ' | ' + payload[:params].inspect : '')
      end
    end
  end
end
