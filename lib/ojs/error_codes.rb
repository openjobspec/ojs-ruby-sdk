# frozen_string_literal: true

module OJS
  # Standardized OJS error codes as defined in the OJS SDK Error Catalog
  # (spec/ojs-error-catalog.md). Each code maps to a canonical wire-format
  # string code from the OJS Error Specification.
  module ErrorCodes
    # A single entry in the OJS error catalog.
    ErrorCodeEntry = Struct.new(:code, :name, :canonical_code, :http_status, :message, :retryable, keyword_init: true) do
      # @return [String] formatted display string
      def to_s
        "[#{code}] #{name}: #{message}"
      end
    end

    # rubocop:disable Layout/LineLength

    # -------------------------------------------------------------------
    # OJS-1xxx: Client Errors
    # -------------------------------------------------------------------

    INVALID_PAYLOAD = ErrorCodeEntry.new(code: "OJS-1000", name: "InvalidPayload", canonical_code: "INVALID_PAYLOAD", http_status: 400, message: "Job envelope fails structural validation", retryable: false)
    INVALID_JOB_TYPE = ErrorCodeEntry.new(code: "OJS-1001", name: "InvalidJobType", canonical_code: "INVALID_JOB_TYPE", http_status: 400, message: "Job type is not registered or does not match the allowlist", retryable: false)
    INVALID_QUEUE = ErrorCodeEntry.new(code: "OJS-1002", name: "InvalidQueue", canonical_code: "INVALID_QUEUE", http_status: 400, message: "Queue name is invalid or does not match naming rules", retryable: false)
    INVALID_ARGS = ErrorCodeEntry.new(code: "OJS-1003", name: "InvalidArgs", canonical_code: "INVALID_ARGS", http_status: 400, message: "Job args fail type checking or schema validation", retryable: false)
    INVALID_METADATA = ErrorCodeEntry.new(code: "OJS-1004", name: "InvalidMetadata", canonical_code: "INVALID_METADATA", http_status: 400, message: "Metadata field is malformed or exceeds the 64 KB size limit", retryable: false)
    INVALID_STATE_TRANSITION = ErrorCodeEntry.new(code: "OJS-1005", name: "InvalidStateTransition", canonical_code: "INVALID_STATE_TRANSITION", http_status: 409, message: "Attempted an invalid lifecycle state change", retryable: false)
    INVALID_RETRY_POLICY = ErrorCodeEntry.new(code: "OJS-1006", name: "InvalidRetryPolicy", canonical_code: "INVALID_RETRY_POLICY", http_status: 400, message: "Retry policy configuration is invalid", retryable: false)
    INVALID_CRON_EXPRESSION = ErrorCodeEntry.new(code: "OJS-1007", name: "InvalidCronExpression", canonical_code: "INVALID_CRON_EXPRESSION", http_status: 400, message: "Cron expression syntax cannot be parsed", retryable: false)
    SCHEMA_VALIDATION_FAILED = ErrorCodeEntry.new(code: "OJS-1008", name: "SchemaValidationFailed", canonical_code: "SCHEMA_VALIDATION_FAILED", http_status: 422, message: "Job args do not conform to the registered schema", retryable: false)
    PAYLOAD_TOO_LARGE = ErrorCodeEntry.new(code: "OJS-1009", name: "PayloadTooLarge", canonical_code: "PAYLOAD_TOO_LARGE", http_status: 413, message: "Job envelope exceeds the server's maximum payload size", retryable: false)
    METADATA_TOO_LARGE = ErrorCodeEntry.new(code: "OJS-1010", name: "MetadataTooLarge", canonical_code: "METADATA_TOO_LARGE", http_status: 413, message: "Metadata field exceeds the 64 KB limit", retryable: false)
    CONNECTION_ERROR = ErrorCodeEntry.new(code: "OJS-1011", name: "ConnectionError", canonical_code: "", http_status: 0, message: "Could not establish a connection to the OJS server", retryable: true)
    REQUEST_TIMEOUT = ErrorCodeEntry.new(code: "OJS-1012", name: "RequestTimeout", canonical_code: "", http_status: 0, message: "HTTP request to the OJS server timed out", retryable: true)
    SERIALIZATION_ERROR = ErrorCodeEntry.new(code: "OJS-1013", name: "SerializationError", canonical_code: "", http_status: 0, message: "Failed to serialize the request or deserialize the response", retryable: false)
    QUEUE_NAME_TOO_LONG = ErrorCodeEntry.new(code: "OJS-1014", name: "QueueNameTooLong", canonical_code: "QUEUE_NAME_TOO_LONG", http_status: 400, message: "Queue name exceeds the 255-byte maximum length", retryable: false)
    JOB_TYPE_TOO_LONG = ErrorCodeEntry.new(code: "OJS-1015", name: "JobTypeTooLong", canonical_code: "JOB_TYPE_TOO_LONG", http_status: 400, message: "Job type exceeds the 255-byte maximum length", retryable: false)
    CHECKSUM_MISMATCH = ErrorCodeEntry.new(code: "OJS-1016", name: "ChecksumMismatch", canonical_code: "CHECKSUM_MISMATCH", http_status: 400, message: "External payload reference checksum verification failed", retryable: false)
    UNSUPPORTED_COMPRESSION = ErrorCodeEntry.new(code: "OJS-1017", name: "UnsupportedCompression", canonical_code: "UNSUPPORTED_COMPRESSION", http_status: 400, message: "The specified compression codec is not supported", retryable: false)

    # -------------------------------------------------------------------
    # OJS-2xxx: Server Errors
    # -------------------------------------------------------------------

    BACKEND_ERROR = ErrorCodeEntry.new(code: "OJS-2000", name: "BackendError", canonical_code: "BACKEND_ERROR", http_status: 500, message: "Internal backend storage or transport failure", retryable: true)
    BACKEND_UNAVAILABLE = ErrorCodeEntry.new(code: "OJS-2001", name: "BackendUnavailable", canonical_code: "BACKEND_UNAVAILABLE", http_status: 503, message: "Backend storage system is unreachable", retryable: true)
    BACKEND_TIMEOUT = ErrorCodeEntry.new(code: "OJS-2002", name: "BackendTimeout", canonical_code: "BACKEND_TIMEOUT", http_status: 504, message: "Backend operation timed out", retryable: true)
    REPLICATION_LAG = ErrorCodeEntry.new(code: "OJS-2003", name: "ReplicationLag", canonical_code: "REPLICATION_LAG", http_status: 500, message: "Operation failed due to replication consistency issue", retryable: true)
    INTERNAL_SERVER_ERROR = ErrorCodeEntry.new(code: "OJS-2004", name: "InternalServerError", canonical_code: "", http_status: 500, message: "Unclassified internal server error", retryable: true)

    # -------------------------------------------------------------------
    # OJS-3xxx: Job Lifecycle Errors
    # -------------------------------------------------------------------

    JOB_NOT_FOUND = ErrorCodeEntry.new(code: "OJS-3000", name: "JobNotFound", canonical_code: "NOT_FOUND", http_status: 404, message: "The requested job, queue, or resource does not exist", retryable: false)
    DUPLICATE_JOB = ErrorCodeEntry.new(code: "OJS-3001", name: "DuplicateJob", canonical_code: "DUPLICATE_JOB", http_status: 409, message: "Unique job constraint was violated", retryable: false)
    JOB_ALREADY_COMPLETED = ErrorCodeEntry.new(code: "OJS-3002", name: "JobAlreadyCompleted", canonical_code: "JOB_ALREADY_COMPLETED", http_status: 409, message: "Operation attempted on a job that has already completed", retryable: false)
    JOB_ALREADY_CANCELLED = ErrorCodeEntry.new(code: "OJS-3003", name: "JobAlreadyCancelled", canonical_code: "JOB_ALREADY_CANCELLED", http_status: 409, message: "Operation attempted on a job that has already been cancelled", retryable: false)
    QUEUE_PAUSED = ErrorCodeEntry.new(code: "OJS-3004", name: "QueuePaused", canonical_code: "QUEUE_PAUSED", http_status: 422, message: "The target queue is paused and not accepting new jobs", retryable: true)
    HANDLER_ERROR = ErrorCodeEntry.new(code: "OJS-3005", name: "HandlerError", canonical_code: "HANDLER_ERROR", http_status: 0, message: "Job handler threw an exception during execution", retryable: true)
    HANDLER_TIMEOUT = ErrorCodeEntry.new(code: "OJS-3006", name: "HandlerTimeout", canonical_code: "HANDLER_TIMEOUT", http_status: 0, message: "Job handler exceeded the configured execution timeout", retryable: true)
    HANDLER_PANIC = ErrorCodeEntry.new(code: "OJS-3007", name: "HandlerPanic", canonical_code: "HANDLER_PANIC", http_status: 0, message: "Job handler caused an unrecoverable error", retryable: true)
    NON_RETRYABLE_ERROR = ErrorCodeEntry.new(code: "OJS-3008", name: "NonRetryableError", canonical_code: "NON_RETRYABLE_ERROR", http_status: 0, message: "Error type matched non_retryable_errors in the retry policy", retryable: false)
    JOB_CANCELLED = ErrorCodeEntry.new(code: "OJS-3009", name: "JobCancelled", canonical_code: "JOB_CANCELLED", http_status: 0, message: "Job was cancelled while it was executing", retryable: false)
    NO_HANDLER_REGISTERED = ErrorCodeEntry.new(code: "OJS-3010", name: "NoHandlerRegistered", canonical_code: "", http_status: 0, message: "No handler is registered for the received job type", retryable: false)

    # -------------------------------------------------------------------
    # OJS-4xxx: Workflow Errors
    # -------------------------------------------------------------------

    WORKFLOW_NOT_FOUND = ErrorCodeEntry.new(code: "OJS-4000", name: "WorkflowNotFound", canonical_code: "", http_status: 404, message: "The specified workflow does not exist", retryable: false)
    CHAIN_STEP_FAILED = ErrorCodeEntry.new(code: "OJS-4001", name: "ChainStepFailed", canonical_code: "", http_status: 422, message: "A step in a chain workflow failed, halting subsequent steps", retryable: false)
    GROUP_TIMEOUT = ErrorCodeEntry.new(code: "OJS-4002", name: "GroupTimeout", canonical_code: "", http_status: 504, message: "A group workflow did not complete within the allowed timeout", retryable: true)
    DEPENDENCY_FAILED = ErrorCodeEntry.new(code: "OJS-4003", name: "DependencyFailed", canonical_code: "", http_status: 422, message: "A required dependency job failed, preventing execution", retryable: false)
    CYCLIC_DEPENDENCY = ErrorCodeEntry.new(code: "OJS-4004", name: "CyclicDependency", canonical_code: "", http_status: 400, message: "The workflow definition contains circular dependencies", retryable: false)
    BATCH_CALLBACK_FAILED = ErrorCodeEntry.new(code: "OJS-4005", name: "BatchCallbackFailed", canonical_code: "", http_status: 422, message: "The batch completion callback job failed", retryable: true)
    WORKFLOW_CANCELLED = ErrorCodeEntry.new(code: "OJS-4006", name: "WorkflowCancelled", canonical_code: "", http_status: 409, message: "The entire workflow was cancelled", retryable: false)

    # -------------------------------------------------------------------
    # OJS-5xxx: Authentication & Authorization Errors
    # -------------------------------------------------------------------

    UNAUTHENTICATED = ErrorCodeEntry.new(code: "OJS-5000", name: "Unauthenticated", canonical_code: "UNAUTHENTICATED", http_status: 401, message: "No authentication credentials provided or credentials are invalid", retryable: false)
    PERMISSION_DENIED = ErrorCodeEntry.new(code: "OJS-5001", name: "PermissionDenied", canonical_code: "PERMISSION_DENIED", http_status: 403, message: "Authenticated but lacks the required permission", retryable: false)
    TOKEN_EXPIRED = ErrorCodeEntry.new(code: "OJS-5002", name: "TokenExpired", canonical_code: "TOKEN_EXPIRED", http_status: 401, message: "The authentication token has expired", retryable: false)
    TENANT_ACCESS_DENIED = ErrorCodeEntry.new(code: "OJS-5003", name: "TenantAccessDenied", canonical_code: "TENANT_ACCESS_DENIED", http_status: 403, message: "Operation on a tenant the caller does not have access to", retryable: false)

    # -------------------------------------------------------------------
    # OJS-6xxx: Rate Limiting & Backpressure Errors
    # -------------------------------------------------------------------

    RATE_LIMITED = ErrorCodeEntry.new(code: "OJS-6000", name: "RateLimited", canonical_code: "RATE_LIMITED", http_status: 429, message: "Rate limit exceeded", retryable: true)
    QUEUE_FULL = ErrorCodeEntry.new(code: "OJS-6001", name: "QueueFull", canonical_code: "QUEUE_FULL", http_status: 429, message: "The queue has reached its configured maximum depth", retryable: true)
    CONCURRENCY_LIMITED = ErrorCodeEntry.new(code: "OJS-6002", name: "ConcurrencyLimited", canonical_code: "", http_status: 429, message: "The concurrency limit has been reached", retryable: true)
    BACKPRESSURE_APPLIED = ErrorCodeEntry.new(code: "OJS-6003", name: "BackpressureApplied", canonical_code: "", http_status: 429, message: "The server is applying backpressure", retryable: true)

    # -------------------------------------------------------------------
    # OJS-7xxx: Extension Errors
    # -------------------------------------------------------------------

    UNSUPPORTED_FEATURE = ErrorCodeEntry.new(code: "OJS-7000", name: "UnsupportedFeature", canonical_code: "UNSUPPORTED_FEATURE", http_status: 422, message: "Feature requires a conformance level the backend does not support", retryable: false)
    CRON_SCHEDULE_CONFLICT = ErrorCodeEntry.new(code: "OJS-7001", name: "CronScheduleConflict", canonical_code: "", http_status: 409, message: "The cron schedule conflicts with an existing schedule", retryable: false)
    UNIQUE_KEY_INVALID = ErrorCodeEntry.new(code: "OJS-7002", name: "UniqueKeyInvalid", canonical_code: "", http_status: 400, message: "The unique key specification is invalid or malformed", retryable: false)
    MIDDLEWARE_ERROR = ErrorCodeEntry.new(code: "OJS-7003", name: "MiddlewareError", canonical_code: "", http_status: 500, message: "An error occurred in the middleware chain", retryable: true)
    MIDDLEWARE_TIMEOUT = ErrorCodeEntry.new(code: "OJS-7004", name: "MiddlewareTimeout", canonical_code: "", http_status: 504, message: "A middleware handler exceeded its allowed execution time", retryable: true)

    # rubocop:enable Layout/LineLength

    # All defined OJS error catalog entries.
    ALL = [
      # OJS-1xxx
      INVALID_PAYLOAD, INVALID_JOB_TYPE, INVALID_QUEUE, INVALID_ARGS,
      INVALID_METADATA, INVALID_STATE_TRANSITION, INVALID_RETRY_POLICY,
      INVALID_CRON_EXPRESSION, SCHEMA_VALIDATION_FAILED, PAYLOAD_TOO_LARGE,
      METADATA_TOO_LARGE, CONNECTION_ERROR, REQUEST_TIMEOUT, SERIALIZATION_ERROR,
      QUEUE_NAME_TOO_LONG, JOB_TYPE_TOO_LONG, CHECKSUM_MISMATCH, UNSUPPORTED_COMPRESSION,
      # OJS-2xxx
      BACKEND_ERROR, BACKEND_UNAVAILABLE, BACKEND_TIMEOUT, REPLICATION_LAG,
      INTERNAL_SERVER_ERROR,
      # OJS-3xxx
      JOB_NOT_FOUND, DUPLICATE_JOB, JOB_ALREADY_COMPLETED, JOB_ALREADY_CANCELLED,
      QUEUE_PAUSED, HANDLER_ERROR, HANDLER_TIMEOUT, HANDLER_PANIC,
      NON_RETRYABLE_ERROR, JOB_CANCELLED, NO_HANDLER_REGISTERED,
      # OJS-4xxx
      WORKFLOW_NOT_FOUND, CHAIN_STEP_FAILED, GROUP_TIMEOUT, DEPENDENCY_FAILED,
      CYCLIC_DEPENDENCY, BATCH_CALLBACK_FAILED, WORKFLOW_CANCELLED,
      # OJS-5xxx
      UNAUTHENTICATED, PERMISSION_DENIED, TOKEN_EXPIRED, TENANT_ACCESS_DENIED,
      # OJS-6xxx
      RATE_LIMITED, QUEUE_FULL, CONCURRENCY_LIMITED, BACKPRESSURE_APPLIED,
      # OJS-7xxx
      UNSUPPORTED_FEATURE, CRON_SCHEDULE_CONFLICT, UNIQUE_KEY_INVALID,
      MIDDLEWARE_ERROR, MIDDLEWARE_TIMEOUT
    ].freeze

    # Look up an entry by its canonical wire-format code (e.g., "INVALID_PAYLOAD").
    # @param canonical [String] the SCREAMING_SNAKE_CASE code
    # @return [ErrorCodeEntry, nil]
    def self.lookup_by_canonical_code(canonical)
      @canonical_index ||= ALL.each_with_object({}) { |e, h| h[e.canonical_code] = e unless e.canonical_code.empty? }.freeze
      @canonical_index[canonical]
    end

    # Look up an entry by its OJS-XXXX numeric code (e.g., "OJS-1000").
    # @param code [String] the OJS-XXXX code
    # @return [ErrorCodeEntry, nil]
    def self.lookup_by_code(code)
      @code_index ||= ALL.each_with_object({}) { |e, h| h[e.code] = e }.freeze
      @code_index[code]
    end
  end
end
