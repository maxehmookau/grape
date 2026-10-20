# frozen_string_literal: true

describe Grape::Endpoint, '#mount_in' do
  let(:counting_middleware) do
    Class.new(Grape::Middleware::Base) do
      class << self
        attr_accessor :built
      end
      self.built = 0

      def initialize(app, **options)
        self.class.built += 1
        super
      end
    end
  end

  context 'with endpoints whose stack settings are equal' do
    let(:app) do
      middleware = counting_middleware
      mounted = Class.new(Grape::API) { get(:mounted) { 'mounted' } }
      Class.new(Grape::API) do
        format :txt
        use middleware
        get(:first) { 'first' }
        get(:second) { 'second' }
        namespace(:nested) { get { 'nested' } }
        mount mounted
      end
    end

    it 'builds one stack that still runs each endpoint' do
      bodies = %w[/first /second /nested /mounted].map { |path| get(path).body }

      expect(bodies).to eq(%w[first second nested mounted])
      expect(counting_middleware.built).to eq(1)
    end
  end

  context 'with namespaces that rescue the same error differently' do
    let(:app) do
      middleware = counting_middleware
      Class.new(Grape::API) do
        use middleware
        namespace(:first) do
          rescue_from(ArgumentError) { error!('first', 422) }
          get { raise ArgumentError }
        end
        namespace(:second) do
          rescue_from(ArgumentError) { error!('second', 409) }
          get { raise ArgumentError }
        end
      end
    end

    it 'gives each namespace its own stack and handler' do
      statuses = %w[/first /second].map { |path| get(path).status }

      expect(statuses).to eq([422, 409])
      expect(counting_middleware.built).to eq(2)
    end
  end

  context 'with the same rescue handlers registered in opposite orders' do
    let(:app) do
      standard_error = proc { error!('standard', 409) }
      argument_error = proc { error!('argument', 422) }
      Class.new(Grape::API) do
        namespace(:argument_first) do
          rescue_from(StandardError, &standard_error)
          namespace(:inner) do
            rescue_from(ArgumentError, &argument_error)
            get { raise ArgumentError }
          end
        end
        namespace(:standard_first) do
          rescue_from(ArgumentError, &argument_error)
          namespace(:inner) do
            rescue_from(StandardError, &standard_error)
            get { raise ArgumentError }
          end
        end
      end
    end

    it 'matches each against its own order' do
      statuses = %w[/argument_first/inner /standard_first/inner].map { |path| get(path).status }

      expect(statuses).to eq([422, 409])
    end
  end

  context 'with the same content types declared in opposite orders' do
    let(:app) do
      Class.new(Grape::API) do
        namespace(:json_first) do
          content_type :json, 'application/json'
          content_type :txt, 'text/plain'
          get { 'page' }
        end
        namespace(:txt_first) do
          content_type :txt, 'text/plain'
          content_type :json, 'application/json'
          get { 'page' }
        end
      end
    end

    it "answers a browser's */* in the type each declares first" do
      browser_accept = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'

      content_types = %w[/json_first /txt_first].map { |path| get(path, {}, 'HTTP_ACCEPT' => browser_accept).content_type }

      expect(content_types).to eq(%w[application/json text/plain])
    end
  end

  context 'with middleware used in one namespace only' do
    let(:app) do
      tagging = Class.new(Grape::Middleware::Base) do
        def before
          env['tagged'] = true
        end
      end
      Class.new(Grape::API) do
        format :txt
        namespace(:tagged) do
          use tagging
          get { env.key?('tagged').to_s }
        end
        get(:plain) { env.key?('tagged').to_s }
      end
    end

    it 'runs it for that namespace alone' do
      bodies = %w[/tagged /plain].map { |path| get(path).body }

      expect(bodies).to eq(%w[true false])
    end
  end

  context 'with endpoints under different versions' do
    let(:app) do
      Class.new(Grape::API) do
        format :txt
        version('v1', using: :path) { get(:thing) { 'v1' } }
        version('v2', using: :path) { get(:thing) { 'v2' } }
      end
    end

    it 'keeps each version on its own versioner' do
      bodies = %w[/v1/thing /v2/thing].map { |path| get(path).body }

      expect(bodies).to eq(%w[v1 v2])
    end
  end
end
