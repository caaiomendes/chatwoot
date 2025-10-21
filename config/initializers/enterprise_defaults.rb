# frozen_string_literal: true

# Ensure every deployment runs in enterprise mode with all features enabled.
Rails.application.config.after_initialize do
  unless Rails.configuration.instance_variable_defined?(:@enterprise_defaults_initialized)
    begin
      ActiveRecord::Base.connection
    rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad, ActiveRecord::StatementInvalid => e
      Rails.logger.warn("Skipping enterprise defaults setup: #{e.class} - #{e.message}")
      next
    end

    ensure_config = lambda do |name, value|
      config = InstallationConfig.find_or_initialize_by(name: name)
      return if config.value == value

      config.value = value
      config.locked = true if config.locked.nil?
      config.save!
    end

    ensure_config.call('INSTALLATION_PRICING_PLAN', 'enterprise')
    ensure_config.call('INSTALLATION_PRICING_PLAN_QUANTITY', ChatwootApp.max_limit)

    features = YAML.safe_load(Rails.root.join('config/features.yml').read)
    features_all_enabled = features.map { |feature| feature.merge('enabled' => true) }

    features_config = InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    if features_config.value != features_all_enabled
      features_config.value = features_all_enabled
      features_config.locked = true if features_config.locked.nil?
      features_config.save!
    end

    feature_names = features_all_enabled.map { |feature| feature['name'] }
    Account.find_each do |account|
      missing_features = feature_names.reject { |feature| account.feature_enabled?(feature) }
      account.enable_features!(*missing_features) if missing_features.any?
    end

    GlobalConfig.clear_cache
    Rails.configuration.instance_variable_set(:@enterprise_defaults_initialized, true)
  end
end
