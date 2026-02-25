# frozen_string_literal: true

module OJS
  # Ordered middleware chain following the Sidekiq/Rack yield-based pattern.
  #
  # Middleware blocks receive (ctx, &next_handler) and call next_handler.call
  # to continue the chain:
  #
  #   chain.add("logging") do |ctx, &nxt|
  #     puts "before"
  #     result = nxt.call
  #     puts "after"
  #     result
  #   end
  #
  class MiddlewareChain
    Entry = Struct.new(:name, :callable)

    def initialize
      @entries = []
      @mutex = Mutex.new
    end

    # Append a middleware to the end of the chain.
    #
    # @param name [String, nil] optional name for later manipulation
    # @yield [ctx, &next_handler] middleware block
    def add(name = nil, &block)
      raise ArgumentError, "block required" unless block

      @mutex.synchronize { @entries << Entry.new(name, block) }
      self
    end
    alias_method :use, :add

    # Prepend a middleware to the beginning of the chain.
    def prepend(name = nil, &block)
      raise ArgumentError, "block required" unless block

      @mutex.synchronize { @entries.unshift(Entry.new(name, block)) }
      self
    end

    # Insert a middleware before the named entry.
    def insert_before(target_name, name = nil, &block)
      raise ArgumentError, "block required" unless block

      @mutex.synchronize do
        idx = find_index!(target_name)
        @entries.insert(idx, Entry.new(name, block))
      end
      self
    end

    # Insert a middleware after the named entry.
    def insert_after(target_name, name = nil, &block)
      raise ArgumentError, "block required" unless block

      @mutex.synchronize do
        idx = find_index!(target_name)
        @entries.insert(idx + 1, Entry.new(name, block))
      end
      self
    end

    # Remove a named middleware.
    def remove(target_name)
      @mutex.synchronize do
        @entries.reject! { |e| e.name == target_name }
      end
      self
    end

    # Check if a named middleware exists.
    def include?(name)
      @mutex.synchronize { @entries.any? { |e| e.name == name } }
    end

    # Return an array of [name, callable] pairs.
    def entries
      @mutex.synchronize { @entries.map { |e| [e.name, e.callable] } }
    end

    # Number of middleware in the chain.
    def size
      @mutex.synchronize { @entries.size }
    end

    # Execute the middleware chain with a terminal handler.
    #
    # The chain is built as an onion — first-added middleware is the outermost.
    # Each middleware receives (ctx) and a block (&next_handler) that, when
    # called, invokes the next middleware (or the terminal handler).
    #
    # @param ctx [Object] context passed to each middleware
    # @yield terminal handler invoked at the center of the chain
    # @return whatever the terminal handler (or outermost middleware) returns
    def invoke(ctx, &terminal)
      snapshot = @mutex.synchronize { @entries.dup }

      # Build chain from inside out: terminal is the innermost handler
      chain = terminal

      snapshot.reverse_each do |entry|
        next_handler = chain
        chain = proc { entry.callable.call(ctx) { next_handler.call } }
      end

      chain.call
    end

    private

    def find_index!(name)
      idx = @entries.index { |e| e.name == name }
      raise ArgumentError, "middleware '#{name}' not found" unless idx

      idx
    end
  end
end

