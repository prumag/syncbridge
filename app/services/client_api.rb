module ClientApi
  Config = Struct.new(:base_url, :token, keyword_init: true)

  def self.config
    @config ||= Config.new(
      base_url: ENV.fetch("CLIENT_API_URL", "http://localhost:4567"),
      token: ENV.fetch("CLIENT_API_TOKEN", "test-token")
    )
  end

  def self.reset_config!
    @config = nil
  end
end
