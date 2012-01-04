require 'sunspot'
require 'mongoid'
require 'sunspot/rails'

# == Examples:
#
# class Post
#   include Mongoid::Document
#   field :title
# 
#   include Sunspot::Mongoid
#   searchable do
#     text :title
#   end
# end
#
module Sunspot
  module Mongoid
    def self.included(base)
      base.class_eval do
        extend Sunspot::Rails::Searchable::ActsAsMethods
        extend Sunspot::Mongoid::ActsAsMethods
        Sunspot::Adapters::DataAccessor.register(DataAccessor, base)
        Sunspot::Adapters::InstanceAdapter.register(InstanceAdapter, base)
        after_destroy :_remove_index
        after_save :_update_index
      end
    end

    module ActsAsMethods
      # ClassMethods isn't loaded until searchable is called so we need
      # call it, then extend our own ClassMethods.
      def searchable (opt = {}, &block)
        super
        extend ClassMethods
      end
    end

    module ClassMethods
      # The sunspot solr_index method is very dependent on ActiveRecord, so
      # we'll change it to work more efficiently with Mongoid.
      def solr_index(opt={})
        0.step(count, 5000) do |offset|
          records = []
          limit(5000).skip(offset).each do |r|
            records << r
          end
          Sunspot.index(records)
        end
        Sunspot.commit
      end
    end


    class InstanceAdapter < Sunspot::Adapters::InstanceAdapter
      def id
        @instance.id.to_s
      end
    end

    class DataAccessor < Sunspot::Adapters::DataAccessor
      def load(id)
        criteria(id).first
      end

      def load_all(ids)
        criteria(ids)
      end

      private

      def criteria(id)
        @clazz.criteria.find(id)
      end
    end
    def _remove_index
      Sunspot.remove! self
    end
    def _update_index
      Sunspot.index! self
    end
  end
  
  class <<self
    attr_writer :configuration

    def configuration(path = nil)
      @configuration ||= Sunspot::Mongoid::Configuration.new(path)
    end

    def reset
      @configuration = nil
    end
    def build_session(configuration = self.configuration)
      if configuration.has_master?
        SessionProxy::MasterSlaveSessionProxy.new(
          SessionProxy::ThreadLocalSessionProxy.new(master_config(configuration)),
          SessionProxy::ThreadLocalSessionProxy.new(slave_config(configuration))
        )
      else
        SessionProxy::ThreadLocalSessionProxy.new(slave_config(configuration))
      end
    end
    private

    def master_config(sunspot_mongoid_configuration)
      config = Sunspot::Configuration.build
      config.solr.url = URI::HTTP.build(
        :host => sunspot_mongoid_configuration.master_hostname,
        :port => sunspot_mongoid_configuration.master_port,
        :path => sunspot_mongoid_configuration.master_path
      ).to_s
      config
    end

    def slave_config(sunspot_mongoid_configuration)
      config = Sunspot::Configuration.build
      config.solr.url = URI::HTTP.build(
        :host => sunspot_mongoid_configuration.hostname,
        :port => sunspot_mongoid_configuration.port,
        :path => sunspot_mongoid_configuration.path
      ).to_s
      config
    end
  end
end
