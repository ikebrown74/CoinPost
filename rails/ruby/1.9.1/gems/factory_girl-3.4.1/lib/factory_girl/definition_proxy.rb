module FactoryGirl
  class DefinitionProxy
    UNPROXIED_METHODS = %w(__send__ __id__ nil? send object_id extend instance_eval initialize block_given? raise caller)

    (instance_methods + private_instance_methods).each do |method|
      undef_method(method) unless UNPROXIED_METHODS.include?(method.to_s)
    end

    attr_reader :child_factories

    def initialize(definition, ignore = false)
      @definition      = definition
      @ignore          = ignore
      @child_factories = []
    end

    # Adds an attribute that should be assigned on generated instances for this
    # factory.
    #
    # This method should be called with either a value or block, but not both. If
    # called with a block, the attribute will be generated "lazily," whenever an
    # instance is generated. Lazy attribute blocks will not be called if that
    # attribute is overridden for a specific instance.
    #
    # When defining lazy attributes, an instance of FactoryGirl::Strategy will
    # be yielded, allowing associations to be built using the correct build
    # strategy.
    #
    # Arguments:
    # * name: +Symbol+ or +String+
    #   The name of this attribute. This will be assigned using "name=" for
    #   generated instances.
    # * value: +Object+
    #   If no block is given, this value will be used for this attribute.
    def add_attribute(name, value = nil, &block)
      raise AttributeDefinitionError, 'Both value and block given' if value && block_given?

      declaration = if block_given?
        Declaration::Dynamic.new(name, @ignore, block)
      else
        Declaration::Static.new(name, value, @ignore)
      end

      @definition.declare_attribute(declaration)
    end

    def ignore(&block)
      proxy = DefinitionProxy.new(@definition, true)
      proxy.instance_eval(&block)
    end

    # Calls add_attribute using the missing method name as the name of the
    # attribute, so that:
    #
    #   factory :user do
    #     name 'Billy Idol'
    #   end
    #
    # and:
    #
    #   factory :user do
    #     add_attribute :name, 'Billy Idol'
    #   end
    #
    # are equivalent.
    #
    # If no argument or block is given, factory_girl will look for a sequence
    # or association with the same name. This means that:
    #
    #   factory :user do
    #     email { create(:email) }
    #     association :account
    #   end
    #
    # and:
    #
    #   factory :user do
    #     email
    #     account
    #   end
    #
    # are equivalent.
    def method_missing(name, *args, &block)
      if args.empty? && block.nil?
        @definition.declare_attribute(Declaration::Implicit.new(name, @definition, @ignore))
      elsif args.first.respond_to?(:has_key?) && args.first.has_key?(:factory)
        association(name, *args)
      elsif FactoryGirl.callback_names.include?(name)
        callback_when, callback_name = name.to_s.split('_', 2)
        ActiveSupport::Deprecation.warn "Calling #{name} is deprecated; use the syntax #{callback_when}(:#{callback_name}) {}", caller
        @definition.add_callback(Callback.new(name, block))
      else
        add_attribute(name, *args, &block)
      end
    end

    # Adds an attribute that will have unique values generated by a sequence with
    # a specified format.
    #
    # The result of:
    #   factory :user do
    #     sequence(:email) { |n| "person#{n}@example.com" }
    #   end
    #
    # Is equal to:
    #   sequence(:email) { |n| "person#{n}@example.com" }
    #
    #   factory :user do
    #     email { FactoryGirl.create(:email) }
    #   end
    #
    # Except that no globally available sequence will be defined.
    def sequence(name, *args, &block)
      sequence = Sequence.new(name, *args, &block)
      add_attribute(name) { sequence.next }
    end

    # Adds an attribute that builds an association. The associated instance will
    # be built using the same build strategy as the parent instance.
    #
    # Example:
    #   factory :user do
    #     name 'Joey'
    #   end
    #
    #   factory :post do
    #     association :author, factory: :user
    #   end
    #
    # Arguments:
    # * name: +Symbol+
    #   The name of this attribute.
    # * options: +Hash+
    #
    # Options:
    # * factory: +Symbol+ or +String+
    #    The name of the factory to use when building the associated instance.
    #    If no name is given, the name of the attribute is assumed to be the
    #    name of the factory. For example, a "user" association will by
    #    default use the "user" factory.
    def association(name, options = {})
      @definition.declare_attribute(Declaration::Association.new(name, options))
    end

    def to_create(&block)
      @definition.to_create(&block)
    end

    def skip_create
      @definition.skip_create
    end

    def factory(name, options = {}, &block)
      @child_factories << [name, options, block]
    end

    def trait(name, &block)
      @definition.define_trait(Trait.new(name, &block))
    end

    def initialize_with(&block)
      @definition.define_constructor(&block)
    end

    def before(name, &block)
      callback("before_#{name}", &block)
    end

    def after(name, &block)
      callback("after_#{name}", &block)
    end

    def callback(name, &block)
      FactoryGirl.register_callback(name)
      @definition.add_callback(Callback.new(name, block))
    end
  end
end
