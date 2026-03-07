# frozen_string_literal: true

require "openssl"
require "base64"
require "securerandom"
require "json"

module OJS
  module Encryption
    META_CODEC_ENCODINGS = "ojs.codec.encodings"
    META_CODEC_KEY_ID    = "ojs.codec.key_id"

    ENCODING_BINARY_ENCRYPTED = "binary/encrypted"

    # Legacy meta keys for backward compatibility on decrypt
    LEGACY_META_ENCRYPTED = "ojs.encryption.encrypted"
    LEGACY_META_ALGORITHM = "ojs.encryption.algorithm"
    LEGACY_META_KEY_ID    = "ojs.encryption.key_id"

    # Interface for key providers. Include this module and implement
    # +get_key(key_id)+ and +current_key_id+.
    module KeyProvider
      def get_key(_key_id)
        raise NotImplementedError, "#{self.class}#get_key not implemented"
      end

      def current_key_id
        raise NotImplementedError, "#{self.class}#current_key_id not implemented"
      end
    end

    # Simple key provider backed by an in-memory Hash.
    class StaticKeyProvider
      include KeyProvider

      KEY_SIZE = 32

      attr_reader :current_key_id

      # @param keys [Hash{String => String}] key_id to 32-byte key mapping
      # @param current_key_id [String] the key id used for encryption
      def initialize(keys, current_key_id)
        keys.each do |id, key|
          unless key.is_a?(String) && key.bytesize == KEY_SIZE
            raise ArgumentError, "key '#{id}' must be #{KEY_SIZE} bytes"
          end
        end
        raise ArgumentError, "current key '#{current_key_id}' not found" unless keys.key?(current_key_id)

        @keys = keys.each_with_object({}) { |(k, v), h| h[k] = v.dup.freeze }.freeze
        @current_key_id = current_key_id.freeze
      end

      # @param key_id [String]
      # @return [String] raw key bytes
      def get_key(key_id)
        @keys.fetch(key_id) { raise ArgumentError, "unknown key: #{key_id}" }
      end
    end

    # AES-256-GCM encryption codec.
    #
    # +encrypt+ returns a single binary blob: nonce (12 B) || ciphertext || auth_tag (16 B).
    # +decrypt+ reverses the process.
    class EncryptionCodec
      NONCE_SIZE = 12
      TAG_SIZE   = 16

      # @param plaintext [String] data to encrypt
      # @param key [String] 32-byte AES key
      # @return [String] binary blob: nonce + ciphertext + auth_tag
      def encrypt(plaintext, key)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = key
        nonce = cipher.random_iv
        cipher.auth_data = ""
        ciphertext = cipher.update(plaintext) + cipher.final
        tag = cipher.auth_tag(TAG_SIZE)
        nonce + ciphertext + tag
      end

      # @param data [String] binary blob produced by +encrypt+
      # @param key [String] 32-byte AES key
      # @return [String] decrypted plaintext
      def decrypt(data, key)
        raise ArgumentError, "data too short" if data.bytesize < NONCE_SIZE + TAG_SIZE

        nonce      = data.byteslice(0, NONCE_SIZE)
        tag        = data.byteslice(-TAG_SIZE, TAG_SIZE)
        ciphertext = data.byteslice(NONCE_SIZE, data.bytesize - NONCE_SIZE - TAG_SIZE)

        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = key
        cipher.iv = nonce
        cipher.auth_tag = tag
        cipher.auth_data = ""
        cipher.update(ciphertext) + cipher.final
      end
    end

    # Returns a middleware proc for the enqueue side.
    #
    # JSON-encodes args, encrypts, Base64-encodes the result into +args[0]+,
    # and sets encryption metadata on the job.
    #
    # @param codec [EncryptionCodec]
    # @param keys [#get_key, #current_key_id] key provider
    # @return [Proc] middleware compatible with +MiddlewareChain+
    def self.encryption_middleware(codec, keys)
      proc do |ctx, &nxt|
        job    = ctx.job
        key_id = keys.current_key_id
        key    = keys.get_key(key_id)

        plaintext = JSON.generate(job.args)
        encrypted = codec.encrypt(plaintext, key)
        encoded   = Base64.strict_encode64(encrypted)

        job.instance_variable_set(:@args, [encoded])
        job.meta[META_CODEC_ENCODINGS] = [ENCODING_BINARY_ENCRYPTED]
        job.meta[META_CODEC_KEY_ID]    = key_id

        nxt.call
      end
    end

    # Returns a middleware proc for the worker side.
    #
    # Checks the encryption flag in meta, Base64-decodes +args[0]+, decrypts,
    # JSON-parses, and restores the original args on the job.
    #
    # @param codec [EncryptionCodec]
    # @param keys [#get_key, #current_key_id] key provider
    # @return [Proc] middleware compatible with +MiddlewareChain+
    def self.decryption_middleware(codec, keys)
      proc do |ctx, &nxt|
        job  = ctx.job
        meta = job.meta

        # Check spec-canonical ojs.codec.encodings for "binary/encrypted"
        encodings = meta[META_CODEC_ENCODINGS]
        is_encrypted = encodings.is_a?(Array) && encodings.include?(ENCODING_BINARY_ENCRYPTED)

        # Backward compat: check legacy ojs.encryption.encrypted flag
        is_encrypted ||= meta[LEGACY_META_ENCRYPTED] == true

        if is_encrypted
          key_id = meta[META_CODEC_KEY_ID] || meta[LEGACY_META_KEY_ID]
          key    = keys.get_key(key_id)

          encrypted = Base64.strict_decode64(job.args[0])
          decrypted = codec.decrypt(encrypted, key)
          restored  = JSON.parse(decrypted)

          job.instance_variable_set(:@args, restored)
        end

        nxt.call
      end
    end
  end
end
