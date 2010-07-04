# encoding: utf-8

# This module allows you to easily cache all responses from the backend - thus
# speeding up the I18n aspects of your application quite a bit.
#
# To enable caching you can simply include the Cache module to the Simple
# backend - or whatever other backend you are using:
#
#   I18n::Backend::Simple.send(:include, I18n::Backend::Cache)
#
# You will also need to set a cache store implementation that you want to use:
#
#   I18n.cache_store = ActiveSupport::Cache.lookup_store(:memory_store)
#
# You can use any cache implementation you want that provides the same API as
# ActiveSupport::Cache (only the methods #fetch and #write are being used).
#
# The cache_key implementation assumes that you only pass values to
# I18n.translate that return a valid key from #hash (see
# http://www.ruby-doc.org/core/classes/Object.html#M000337).
#
# If you use a lambda as a default value in your translation like this:
#
#   I18n.t(:"date.order", :default => lambda {[:month, :day, :year]})
#
# Then you will always have a cache miss, because each time this method
# is called the lambda will have a different hash value. If you know
# the result of the lambda is a constant as in the example above, then
# to cache this you can make the lambda a constant, like this:
#
#   DEFAULT_DATE_ORDER = lambda {[:month, :day, :year]}
#   ...
#   I18n.t(:"date.order", :default => DEFAULT_DATE_ORDER)
#
# If the lambda may result in different values for each call then consider
# also using the Memoize backend.
#
module I18n
  class << self
    @@cache_store = nil
    @@cache_namespace = nil
    @@cache_version = nil
    @@cache_version_time = nil
    CACHE_VERSION_FETCH_INTERVAL = 5.seconds

    def cache_store
      @@cache_store
    end

    def cache_store=(store)
      @@cache_store = store
    end

    def cache_namespace
      @@cache_namespace
    end

    def cache_namespace=(namespace)
      @@cache_namespace = namespace
    end

    def cache_version
      unless @@cache_version_time && @@cache_version_time + CACHE_VERSION_FETCH_INTERVAL > Time.now
        cache_version_initialize
        @@cache_version = nil
      end
      unless @@cache_version
        @@cache_version = I18n.cache_store.read("i18n-version", :raw => true).to_i
        @@cache_version_time = Time.now
      end
      @@cache_version
    end

    def cache_invalidate!
      I18n.cache_store.increment("i18n-version")
    end

    def cache_version_initialize
      unless I18n.cache_store.read("i18n-version", :raw => true)
        I18n.cache_store.write("i18n-version", 0, :raw => true)
      end
    end

    def perform_caching?
      !cache_store.nil?
    end
  end

  module Backend
    # TODO Should the cache be cleared if new translations are stored?
    module Cache
      def translate(locale, key, options = {})
        I18n.perform_caching? ? fetch(cache_key(locale, key, options)) { super } : super
      end

      protected

        def fetch(cache_key, &block)
          result = begin
            I18n.cache_store.fetch(cache_key, &block)
          rescue MissingTranslationData => exception
            I18n.cache_store.write(cache_key, exception)
            exception
          end
          raise result if result.is_a?(Exception)
          result = result.dup if result.frozen? rescue result
          result
        end

        def cache_key(locale, key, options)
          # This assumes that only simple, native Ruby values are passed to I18n.translate.
          # Also, in Ruby < 1.8.7 {}.hash != {}.hash
          # (see http://paulbarry.com/articles/2009/09/14/why-rails-3-will-require-ruby-1-8-7)
          # If args.inspect does not work for you for some reason, patches are very welcome :)
          ['i18n', I18n.cache_namespace, locale, key.hash, RUBY_VERSION >= "1.8.7" ? options.hash : options.inspect.hash, I18n.cache_version].join('/')
        end
    end
  end
end