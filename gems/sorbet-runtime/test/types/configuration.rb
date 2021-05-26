# frozen_string_literal: true
require_relative '../test_helper'

module Opus::Types::Test
  class ConfigurationTest < Critic::Unit::UnitTest
    before do
      @mod = Module.new do
        extend T::Sig
        # Make it public for testing only
        public_class_method :sig
      end
    end

    class CustomReceiver
      def self.receive(*); end
    end

    module Readable; end
    module Writable
      def write
        T.bind(self, T.all(Readable, Writable))
        true
      end
    end

    class BadArticle
      include Writable
    end

    class GoodArticle
      include Writable
      include Readable
    end

    describe 'inline_type_error_handler' do
      describe 'when in default state' do
        it 'T.must raises an error' do
          assert_raises(TypeError) do
            T.must(nil)
          end
        end

        it 'T.let raises an error' do
          assert_raises(TypeError) do
            T.let(1, String)
          end
        end

        it 'T.bind raises an error if block is executing on the wrong type' do
          block = -> {T.bind(self, String); upcase}

          assert_raises(TypeError) do
            123.instance_exec(&block)
          end
        end

        it 'T.bind raises error if type constraints are not all satisfied' do
          bad_article = BadArticle.new

          assert_raises(TypeError) do
            bad_article.write
          end

          good_article = GoodArticle.new
          assert good_article.write
        end
      end

      describe 'when overridden' do
        before do
          T::Configuration.inline_type_error_handler = lambda do |*args|
            CustomReceiver.receive(*args)
          end
        end

        after do
          T::Configuration.inline_type_error_handler = nil
        end

        it 'handles a T.must error' do
          CustomReceiver.expects(:receive).once.with do |error|
            error.is_a?(TypeError)
          end
          assert_nil(T.must(nil))
        end

        it 'handles a T.let error' do
          CustomReceiver.expects(:receive).once.with do |error|
            error.is_a?(TypeError)
          end
          assert_equal(1, T.let(1, String))
        end
      end
    end

    describe 'sig_builder_error_handler' do
      describe 'when in default state' do
        it 'raises an error' do
          @mod.sig {returns(Symbol).void}
          def @mod.foo
            :bar
          end
          ex = assert_raises(ArgumentError) do
            @mod.foo
          end
          assert_includes(
            ex.message,
            "You can't call .void after calling .returns."
          )
        end
      end

      describe 'when overridden' do
        before do
          T::Configuration.sig_builder_error_handler = lambda do |*args|
            CustomReceiver.receive(*args)
          end
        end

        after do
          T::Configuration.sig_builder_error_handler = nil
        end

        it 'handles a sig builder error' do
          CustomReceiver.expects(:receive).once.with do |error, location|
            error.message == "You can't call .void after calling .returns." &&
              error.is_a?(T::Private::Methods::DeclBuilder::BuilderError) &&
              location.is_a?(Thread::Backtrace::Location)
          end
          @mod.sig {returns(Symbol).void}
          def @mod.foo
            :bar
          end
          assert_equal(:bar, @mod.foo)
        end
      end
    end

    describe 'sig_validation_error_handler' do
      describe 'when in default state' do
        it 'raises an error' do
          @mod.sig {override.returns(Symbol)}
          def @mod.foo
            :bar
          end
          ex = assert_raises(RuntimeError) do
            @mod.foo
          end
          assert_includes(
            ex.message,
            "You marked `foo` as .override, but that method doesn't already exist"
          )
        end
      end

      describe 'when overridden' do
        before do
          T::Configuration.sig_validation_error_handler = lambda do |*args|
            CustomReceiver.receive(*args)
          end
        end

        after do
          T::Configuration.sig_validation_error_handler = nil
        end

        it 'handles a sig build error' do
          CustomReceiver.expects(:receive).once.with do |error, opts|
            error.message.include?("You marked `foo` as .override, but that method doesn't already exist") &&
              error.is_a?(RuntimeError) &&
              opts.is_a?(Hash) &&
              opts[:method].is_a?(UnboundMethod) &&
              opts[:declaration].is_a?(T::Private::Methods::Declaration) &&
              opts[:signature].is_a?(T::Private::Methods::Signature)
          end

          @mod.sig {override.returns(Symbol)}
          def @mod.foo
            :bar
          end
          assert_equal(:bar, @mod.foo)
        end
      end
    end

    describe 'final_checks_on_hooks' do
      describe 'when in default state' do
        it 'raises an error' do
          @mod.sig(:final) {returns(Symbol)}
          def @mod.final_method_redefined_ko
            :bar
          end
          ex = assert_raises(RuntimeError) do
            @mod.sig(:final) {returns(Symbol)}
            def @mod.final_method_redefined_ko
              :baz
            end
          end
          assert_includes(ex.message, "was declared as final and cannot be redefined")
        end
      end

      describe 'when overridden' do
        before do
          T::Configuration.sig_validation_error_handler = lambda do |*args|
            CustomReceiver.receive(*args)
          end
        end

        after do
          T::Configuration.sig_validation_error_handler = nil
        end

        it 'handles a final method redefinition error' do
          CustomReceiver.expects(:receive).once.with do |error, opts|
            error.message.include?("was declared as final and cannot be redefined") &&
              error.is_a?(RuntimeError) &&
              opts.is_a?(Hash) &&
              opts.empty?
          end

          @mod.sig(:final) {returns(Symbol)}
          def @mod.final_method_redefined_ok
            :bar
          end
          assert_equal(:bar, @mod.final_method_redefined_ok)
          @mod.sig(:final) {returns(Symbol)}
          def @mod.final_method_redefined_ok
            :baz
          end
          assert_equal(:baz, @mod.final_method_redefined_ok)
        end
      end
    end

    describe 'call_validation_error_handler' do
      describe 'when in default state' do
        it 'raises an error' do
          @mod.sig {params(a: String).returns(Symbol)}
          def @mod.foo(a)
            :bar
          end
          ex = assert_raises(TypeError) do
            @mod.foo(1)
          end
          assert_includes(
            ex.message,
            "Parameter 'a': Expected type String, got type Integer with value 1"
          )
        end
      end

      describe 'when overridden' do
        before do
          T::Configuration.call_validation_error_handler = lambda do |*args|
            CustomReceiver.receive(*args)
          end
        end

        after do
          T::Configuration.call_validation_error_handler = nil
        end

        it 'handles a sig error' do
          CustomReceiver.expects(:receive).once.with do |signature, opts|
            signature.is_a?(T::Private::Methods::Signature) &&
              opts.is_a?(Hash) &&
              opts[:name] == :a &&
              opts[:kind] == 'Parameter' &&
              opts[:type].name == 'String' &&
              opts[:value] == 1 &&
              opts[:location].is_a?(Thread::Backtrace::Location) &&
              opts[:message].include?("Expected type String, got type Integer with value 1")
          end
          @mod.sig {params(a: String).returns(Symbol)}
          def @mod.foo(a)
            :bar
          end
          assert_equal(:bar, @mod.foo(1))
        end
      end
    end

    describe 'scalar_types' do
      describe 'when overridden' do
        it 'requires string values' do
          ex = assert_raises(ArgumentError) do
            T::Configuration.scalar_types = [1, 2, 3]
          end
          assert_includes(ex.message, "Provided values must all be class name strings.")
        end
      end
    end

    describe 'exclude_value_in_type_errors' do
      describe 'when in default state' do
        it 'raises an error with a message including the value' do
          e = assert_raises(TypeError) do
            T.let("foo", Integer)
          end
          assert_equal('T.let: Expected type Integer, got type String with value "foo"', e.message.split("\n").first)
        end
      end

      describe 'when explicitly include' do
        it 'raises an error with a message including the value' do
          T::Configuration.include_value_in_type_errors
          e = assert_raises(TypeError) do
            T.let("foo", Integer)
          end
          assert_equal('T.let: Expected type Integer, got type String with value "foo"', e.message.split("\n").first)
        end
      end

      describe 'when exclude' do
        before do
          T::Configuration.exclude_value_in_type_errors
        end
        after do
          T::Configuration.include_value_in_type_errors
        end

        it 'raises an error with a message including the value' do
          e = assert_raises(TypeError) do
            T.let("foo", Integer)
          end
          assert_equal('T.let: Expected type Integer, got type String', e.message.split("\n").first)
        end
      end

      describe 'enable_vm_prop_serde' do
        it "fails if the VM doesn't support it" do
          return if T::Configuration.can_enable_vm_prop_serde?

          assert_raises(RuntimeError) do
            T::Configuration.enable_vm_prop_serde
          end
        end

        it "succeeds if the VM does support it" do
          return unless T::Configuration.can_enable_vm_prop_serde?

          was_enabled = T::Configuration.use_vm_prop_serde?

          begin
            T::Configuration.enable_vm_prop_serde
          ensure
            T::Configuration.disable_vm_prop_serde unless was_enabled
          end
        end
      end
    end

    describe 'runtime_type_assertions' do
      describe 'when in default state' do
        # Default behaviours for other assertions are checked
        # elsewhere in this file
        it 'T.cast raises an error' do
          assert_raises(TypeError) do
            T.cast(1, String)
          end
        end

        it 'T.absurd raises an error' do
          assert_raises(TypeError) do
            T.absurd("Hello")
          end
        end
      end

      describe 'when overridden' do
        before do
          T::Configuration.disable_runtime_type_assertions
        end

        it 'T.let returns the given value without error' do
          assert_equal 1, T.let(1, String)
        end

        it 'T.cast returns the given value without error' do
          assert_equal 1, T.cast(1, String)
        end

        it 'T.must returns nil without error' do
          assert_nil T.must(nil)
        end

        it 'T.absurd returns the given value without error' do
          assert_equal "Hello", T.absurd("Hello")
        end

        it 'T.bind returns the given value without error' do
          assert_equal 123, T.bind(123, String)
        end

        after do
          T::Configuration.remove_instance_variable(:@runtime_type_assertions_enabled)
        end
      end
    end
  end
end
