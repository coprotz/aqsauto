const {
  QUICKLIPA_API_KEY,
  QUICKLIPA_APP_ID,
  QUICKLIPA_BASE_URL,
} = require(
    "../config/quicklipa.config",
);

/**
 * Convert value to trimmed string.
 *
 * @param {*} value Raw value.
 * @return {string}
 */
function readString(value) {
  if (
    value === null ||
    value === undefined
  ) {
    return "";
  }

  return String(value).trim();
}

/**
 * Normalize supported mobile-money providers
 * into QuickLipa canonical provider values.
 *
 * @param {*} value Raw provider.
 * @return {string}
 */
function normalizeProvider(value) {
  const provider =
      readString(value)
          .toLowerCase();

  switch (provider) {
    case "airtel":
    case "airtelmoney":
    case "airtel money":
      return "Airtel";

    case "tigo":
    case "mixx":
    case "mixx by yas":
    case "yas":
    case "tigo pesa":
      return "Tigo";

    case "halopesa":
    case "halo pesa":
      return "Halopesa";

    case "mpesa":
    case "m-pesa":
    case "vodacom":
      return "Mpesa";

    case "azam":
    case "azampesa":
    case "azam pesa":
      return "Azampesa";

    default:
      return "";
  }
}

/**
 * Build a safe idempotency key.
 *
 * @param {Object} input Input data.
 * @param {string} input.userId Firebase UID.
 * @param {string} input.productCode Product code.
 * @param {string} input.applicationReference App reference.
 * @param {number} input.attempt Attempt number.
 * @return {string}
 */
function buildAqsIdempotencyKey(input) {
  const userId =
      readString(
          input && input.userId,
      );

  const productCode =
      readString(
          input && input.productCode,
      );

  const applicationReference =
      readString(
          input &&
          input.applicationReference,
      );

  const attemptNumber =
      input &&
      input.attempt ?
        Number(input.attempt) :
        1;

  function clean(value) {
    return readString(value)
        .replace(
            /[^A-Za-z0-9_-]/g,
            "-",
        )
        .slice(0, 80);
  }

  return [
    "aqs",
    clean(userId),
    clean(productCode),
    clean(applicationReference),
    "attempt-" +
        String(attemptNumber),
  ].join("-");
}

/**
 * Returns true when QuickLipa returned
 * a successful payment.
 *
 * @param {*} payment QuickLipa payment.
 * @return {boolean}
 */
function isSuccessfulQuickLipaPayment(
    payment,
) {
  const status =
      readString(
          payment &&
          payment.status,
      ).toLowerCase();

  const stage =
      readString(
          payment &&
          payment.stage,
      ).toLowerCase();

  return (
    status === "successful" ||
    status === "success" ||
    status === "completed" ||
    stage === "completed"
  );
}

/**
 * Returns true when QuickLipa returned
 * a failed payment.
 *
 * @param {*} payment QuickLipa payment.
 * @return {boolean}
 */
function isFailedQuickLipaPayment(
    payment,
) {
  const status =
      readString(
          payment &&
          payment.status,
      ).toLowerCase();

  const stage =
      readString(
          payment &&
          payment.stage,
      ).toLowerCase();

  return (
    status === "failed" ||
    status === "failure" ||
    status === "cancelled" ||
    status === "canceled" ||
    stage === "failed"
  );
}

/**
 * Extracts the actual payment payload from
 * different QuickLipa response shapes.
 *
 * Supports:
 *
 * {
 *   paymentId: ...
 * }
 *
 * or
 *
 * {
 *   success: true,
 *   data: {
 *     paymentId: ...
 *   }
 * }
 *
 * @param {*} payload QuickLipa JSON payload.
 * @return {Object}
 */
function extractPaymentPayload(payload) {
  if (
    payload &&
    typeof payload === "object" &&
    payload.data &&
    typeof payload.data === "object"
  ) {
    return payload.data;
  }

  if (
    payload &&
    typeof payload === "object"
  ) {
    return payload;
  }

  return {};
}

/**
 * Initiates a payment through QuickLipa.
 *
 * IMPORTANT:
 * Amount is never accepted from AQS.
 * QuickLipa resolves the trusted amount
 * using the productCode.
 *
 * @param {Object} input Payment input.
 * @return {Promise<Object>}
 */
async function initiatePayment(input) {
  const productCode =
      readString(
          input &&
          input.productCode,
      ).toUpperCase();

  const applicationReference =
      readString(
          input &&
          input.applicationReference,
      );

  const provider =
      normalizeProvider(
          input &&
          input.provider,
      );

  const customer =
      input &&
      input.customer &&
      typeof input.customer === "object" ?
        input.customer :
        {};

  const metadata =
      input &&
      input.metadata &&
      typeof input.metadata === "object" ?
        input.metadata :
        {};

  const pricingQuoteId =
      readString(
          input &&
          input.pricingQuoteId,
      );

  const idempotencyKey =
      readString(
          input &&
          input.idempotencyKey,
      );

  if (!productCode) {
    const error =
        new Error(
            "QuickLipa productCode is required.",
        );

    error.code =
        "missing_product_code";

    throw error;
  }

  if (!applicationReference) {
    const error =
        new Error(
            "QuickLipa applicationReference is required.",
        );

    error.code =
        "missing_application_reference";

    throw error;
  }

  if (!provider) {
    const error =
        new Error(
            "Unsupported mobile-money provider.",
        );

    error.code =
        "invalid_provider";

    throw error;
  }

  if (!idempotencyKey) {
    const error =
        new Error(
            "QuickLipa idempotency key is required.",
        );

    error.code =
        "missing_idempotency_key";

    throw error;
  }

  /*
   * Firebase Secret Manager values.
   */
  const appId =
      QUICKLIPA_APP_ID
          .value()
          .trim();

  const apiKey =
      QUICKLIPA_API_KEY
          .value()
          .trim();

  const baseUrl =
      QUICKLIPA_BASE_URL
          .value()
          .trim()
          .replace(
              /\/+$/,
              "",
          );

  if (!appId) {
    throw new Error(
        "QUICKLIPA_APP_ID is empty.",
    );
  }

  if (!apiKey) {
    throw new Error(
        "QUICKLIPA_API_KEY is empty.",
    );
  }

  if (!baseUrl) {
    throw new Error(
        "QUICKLIPA_BASE_URL is empty.",
    );
  }

  const body = {
    productCode:
        productCode,

    applicationReference:
        applicationReference,

    provider:
        provider,

    customer: {
      id:
          readString(
              customer.id,
          ),

      name:
          readString(
              customer.name,
          ),

      email:
          readString(
              customer.email,
          ),

      phone:
          readString(
              customer.phone,
          ),
    },

    metadata:
        metadata,
  };

  /*
   * Only send pricingQuoteId when provided.
   */
  if (pricingQuoteId) {
    body.pricingQuoteId =
        pricingQuoteId;
  }

  const url =
      baseUrl +
      "/v1/payments";

  /*
   * Safe diagnostic.
   * Never log the full API key.
   */
  console.log(
      "QuickLipa request",
      {
        appId:
            appId,

        baseUrl:
            baseUrl,

        productCode:
            productCode,

        provider:
            provider,

        applicationReference:
            applicationReference,

        apiKeyPrefix:
            apiKey.substring(
                0,
                Math.min(
                    12,
                    apiKey.length,
                ),
            ),

        apiKeyLastFour:
            apiKey.length >= 4 ?
              apiKey.slice(-4) :
              "",
      },
  );

  let response;

  try {
    response =
        await fetch(
            url,
            {
              method:
                  "POST",

              headers: {
                "Content-Type":
                    "application/json",

                "Accept":
                    "application/json",

                "X-Application-Id":
                    appId,

                "X-Application-Key":
                    apiKey,

                "Idempotency-Key":
                    idempotencyKey,
              },

              body:
                  JSON.stringify(
                      body,
                  ),
            },
        );
  } catch (networkError) {
    console.error(
        "QuickLipa network error",
        {
          message:
              networkError &&
              networkError.message ?
                networkError.message :
                null,

          stack:
              networkError &&
              networkError.stack ?
                networkError.stack :
                null,
        },
    );

    const error =
        new Error(
            "Could not connect to QuickLipa.",
        );

    error.code =
        "quicklipa_network_error";

    error.status =
        503;

    error.cause =
        networkError;

    throw error;
  }

  let payload = {};

  const rawText =
      await response.text();

  if (rawText) {
    try {
      payload =
          JSON.parse(
              rawText,
          );
    } catch (parseError) {
      payload = {
        raw:
            rawText,
      };
    }
  }

  if (!response.ok) {
    const quickLipaError =
        payload &&
        payload.error &&
        typeof payload.error === "object" ?
          payload.error :
          {};

    const message =
        readString(
            quickLipaError.message,
        ) ||
        readString(
            payload.message,
        ) ||
        "QuickLipa request failed.";

    const code =
        readString(
            quickLipaError.code,
        ) ||
        readString(
            payload.code,
        ) ||
        "quicklipa_request_failed";

    const error =
        new Error(
            message,
        );

    error.status =
        response.status;

    error.code =
        code;

    error.details =
        quickLipaError.details ||
        payload.details ||
        null;

    error.payload =
        payload;

    console.error(
        "QuickLipa API error",
        {
          status:
              response.status,

          code:
              error.code,

          message:
              error.message,

          details:
              error.details,
        },
    );

    throw error;
  }

  const payment =
      extractPaymentPayload(
          payload,
      );

  console.log(
      "QuickLipa response",
      {
        paymentId:
            readString(
                payment.paymentId,
            ),

        externalId:
            readString(
                payment.externalId,
            ),

        status:
            readString(
                payment.status,
            ),

        stage:
            readString(
                payment.stage,
            ),

        productCode:
            readString(
                payment.productCode,
            ),

        amount:
            payment.amount,

        currency:
            readString(
                payment.currency,
            ),
      },
  );

  return payment;
}

module.exports = {
  initiatePayment,
  normalizeProvider,
  buildAqsIdempotencyKey,
  isSuccessfulQuickLipaPayment,
  isFailedQuickLipaPayment,
};
