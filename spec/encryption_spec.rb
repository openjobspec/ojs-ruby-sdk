# frozen_string_literal: true

require_relative "spec_helper"
require "ojs/encryption"

RSpec.describe OJS::Encryption do
  let(:key_a) { OpenSSL::Random.random_bytes(32) }
  let(:key_b) { OpenSSL::Random.random_bytes(32) }
  let(:codec) { OJS::Encryption::EncryptionCodec.new }

  describe OJS::Encryption::EncryptionCodec do
    describe "roundtrip" do
      it "encrypts then decrypts to the original plaintext" do
        plaintext = "hello, open job spec!"
        ciphertext = codec.encrypt(plaintext, key_a)
        result = codec.decrypt(ciphertext, key_a)

        expect(result).to eq(plaintext)
      end
    end

    describe "wrong key" do
      it "raises an error when decrypting with a different key" do
        ciphertext = codec.encrypt("secret data", key_a)

        expect { codec.decrypt(ciphertext, key_b) }.to raise_error(OpenSSL::Cipher::CipherError)
      end
    end

    describe "nonce uniqueness" do
      it "produces different ciphertexts for the same plaintext and key" do
        plaintext = "same input"
        ct1 = codec.encrypt(plaintext, key_a)
        ct2 = codec.encrypt(plaintext, key_a)

        expect(ct1).not_to eq(ct2)
      end
    end

    describe "empty plaintext" do
      it "encrypts and decrypts an empty string" do
        ciphertext = codec.encrypt("", key_a)
        result = codec.decrypt(ciphertext, key_a)

        expect(result).to eq("")
      end
    end

    describe "data too short" do
      it "raises ArgumentError when data is shorter than nonce + tag" do
        short_data = "x" * (OJS::Encryption::EncryptionCodec::NONCE_SIZE + OJS::Encryption::EncryptionCodec::TAG_SIZE - 1)

        expect { codec.decrypt(short_data, key_a) }.to raise_error(ArgumentError, /data too short/)
      end
    end
  end

  describe OJS::Encryption::StaticKeyProvider do
    let(:key_id) { "primary" }
    let(:keys) { { key_id => key_a, "secondary" => key_b } }
    let(:provider) { described_class.new(keys, key_id) }

    describe "#get_key" do
      it "returns the correct key for a known id" do
        expect(provider.get_key("primary")).to eq(key_a)
        expect(provider.get_key("secondary")).to eq(key_b)
      end

      it "raises for an unknown key id" do
        expect { provider.get_key("nonexistent") }.to raise_error(ArgumentError, /unknown key/)
      end
    end

    describe "#current_key_id" do
      it "returns the current key id" do
        expect(provider.current_key_id).to eq(key_id)
      end
    end

    describe "validation" do
      it "raises if a key is not 32 bytes" do
        expect { described_class.new({ "bad" => "short" }, "bad") }.to raise_error(ArgumentError, /must be 32 bytes/)
      end

      it "raises if current_key_id is not in keys" do
        expect { described_class.new({ "a" => key_a }, "missing") }.to raise_error(ArgumentError, /not found/)
      end
    end
  end

  describe "encryption middleware meta keys" do
    let(:key_id) { "test-key" }
    let(:provider) { OJS::Encryption::StaticKeyProvider.new({ key_id => key_a }, key_id) }
    let(:middleware) { OJS::Encryption.encryption_middleware(codec, provider) }

    it "sets ojs.codec.encodings and ojs.codec.key_id on the job" do
      job = OJS::Job.new(type: "email.send", args: [{ "to" => "user@example.com" }])
      ctx = OJS::MiddlewareContext.new(job: job)
      called = false

      middleware.call(ctx) { called = true }

      expect(called).to be true
      expect(job.meta[OJS::Encryption::META_CODEC_ENCODINGS]).to eq([OJS::Encryption::ENCODING_BINARY_ENCRYPTED])
      expect(job.meta[OJS::Encryption::META_CODEC_KEY_ID]).to eq(key_id)
    end

    it "produces args that the decryption middleware can restore" do
      original_args = [{ "to" => "user@example.com" }, 42]
      job = OJS::Job.new(type: "email.send", args: original_args)
      ctx = OJS::MiddlewareContext.new(job: job)

      middleware.call(ctx) { }

      decrypt_mw = OJS::Encryption.decryption_middleware(codec, provider)
      decrypt_mw.call(ctx) { }

      expect(job.args).to eq(original_args)
    end
  end
end
