const {
  onCall,
  HttpsError,
} = require(
    "firebase-functions/v2/https",
);

const {
  getFirestore,
  FieldValue,
} = require(
    "firebase-admin/firestore",
);

const {
  QUICKLIPA_API_KEY,
  QUICKLIPA_APP_ID,
  QUICKLIPA_BASE_URL,
} = require(
    "../config/quicklipa.config",
);

const {
  initiatePayment,
  normalizeProvider,
  buildAqsIdempotencyKey,
} = require(
    "../services/quicklipa.service",
);

const {
  activateSubscription,
} = require(
    "../services/subscription-activation.service",
);

const PAYMENT_ATTEMPTS_COLLECTION =
    "payment-attempts";

const CONNECTOR_ERROR_PREFIXES = [
  "azampay_",
  "quicklipa_",
];

const ALLOWED_PRODUCT_CODES =
    new Set([
      "AQS_BASIC_MONTHLY",
      "AQS_BASIC_YEARLY",
      "AQS_PRO_MONTHLY",
      "AQS_PRO_YEARLY",
      "AQS_BUSINESS_MONTHLY",
      "AQS_BUSINESS_YEARLY",
    ]);

/**
 * Reads a trimmed string.
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
 * Converts QuickLipa/downstream connector failures into a stable AQS-facing
 * error. Internal connector names remain available in server logs and the
 * payment-attempt record, but are not exposed as if AQS called them directly.
 *
 * @param {*} error Raw integration error.
 * @return {{code: string, message: string, status: number}}
 */
function normalizePaymentFailure(error) {
  const rawCode =
      readString(
          error && error.code,
      ).toLowerCase();

  const rawStatus = Number(
      error && error.status,
  );

  const status =
      Number.isFinite(rawStatus) ?
        rawStatus :
        500;

  const isConnectorError =
      CONNECTOR_ERROR_PREFIXES.some(
          (prefix) =>
            rawCode.startsWith(prefix),
      );

  if (
    isConnectorError &&
    status >= 500
  ) {
    return {
      code:
          "quicklipa_provider_unavailable",
      message:
          "The mobile-money provider could not accept the request. " +
          "Please wait a moment, confirm the selected network and phone " +
          "number, then try again.",
      status,
    };
  }

  if (
    isConnectorError ||
    status === 409 ||
    status === 422
  ) {
    return {
      code:
          "quicklipa_checkout_rejected",
      message:
          "The mobile-money network rejected the payment request. " +
          "Confirm the selected network and phone number, then try again.",
      status,
    };
  }

  return {
    code:
        rawCode ||
        "payment_initiation_failed",
    message:
        readString(
            error && error.message,
        ) ||
        "The payment could not be initiated.",
    status,
  };
}

/**
 * Validates callable request.
 *
 * @param {*} rawData Request data.
 * @param {string} authenticatedUid UID.
 * @return {Object}
 */
function validateRequestData(
    rawData,
    authenticatedUid,
) {
  if (
    !rawData ||
    typeof rawData !== "object" ||
    Array.isArray(rawData)
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Payment information is required.",
    );
  }

  const productCode =
      readString(
          rawData.productCode,
      ).toUpperCase();

  const provider =
      normalizeProvider(
          rawData.provider,
      );

  const customerData =
      rawData.customer &&
      typeof rawData.customer ===
      "object" ?
        rawData.customer :
        {};

  const customerName =
      readString(
          customerData.name,
      );

  const customerEmail =
      readString(
          customerData.email,
      ).toLowerCase();

  const customerPhone =
      readString(
          customerData.phone,
      );

  if (
    !ALLOWED_PRODUCT_CODES.has(
        productCode,
    )
  ) {
    throw new HttpsError(
        "invalid-argument",
        "The selected AQS plan is not supported.",
    );
  }

  if (!provider) {
    throw new HttpsError(
        "invalid-argument",
        "Select a valid mobile-money provider.",
    );
  }

  if (!customerPhone) {
    throw new HttpsError(
        "invalid-argument",
        "Customer phone number is required.",
    );
  }

  return {
    userId:
        authenticatedUid,

    productCode:
        productCode,

    provider:
        provider,

    customerName:
        customerName,

    customerEmail:
        customerEmail || null,

    customerPhone:
        customerPhone,
  };
}

/**
 * Creates AQS application reference.
 *
 * @param {string} userId Firebase UID.
 * @param {string} attemptId Attempt ID.
 * @return {string}
 */
function createApplicationReference(
    userId,
    attemptId,
) {
  const userPart =
      userId
          .replace(
              /[^a-zA-Z0-9]/g,
              "",
          )
          .slice(
              0,
              10,
          )
          .toUpperCase();

  const attemptPart =
      attemptId
          .replace(
              /[^a-zA-Z0-9]/g,
              "",
          )
          .slice(
              0,
              12,
          )
          .toUpperCase();

  return [
    "AQS",
    userPart || "USER",
    attemptPart,
  ].join("-");
}

/**
 * Initiates AQS subscription payment.
 */
const initiateAqsPayment =
    onCall(
        {
          region:
              "us-central1",

          secrets: [
            QUICKLIPA_API_KEY,
            QUICKLIPA_APP_ID,
            QUICKLIPA_BASE_URL,
          ],

          timeoutSeconds:
              120,

          memory:
              "256MiB",

          enforceAppCheck:
              false,
        },

        async (request) => {
          let attemptRef = null;
          let applicationReference = "";

          const db =
              getFirestore();

          try {
            const requestAuth =
                request &&
                request.auth ?
                  request.auth :
                  null;

            const requestData =
                request &&
                request.data ?
                  request.data :
                  null;

            const authenticatedUid =
                requestAuth &&
                requestAuth.uid ?
                  String(
                      requestAuth.uid,
                  ) :
                  "";

            console.log(
                "initiateAqsPayment called",
                {
                  authenticated:
                      Boolean(
                          authenticatedUid,
                      ),

                  uid:
                      authenticatedUid ||
                      null,

                  data:
                      requestData ||
                      null,
                },
            );

            if (!authenticatedUid) {
              throw new HttpsError(
                  "unauthenticated",
                  "Sign in before starting a payment.",
              );
            }

            const input =
                validateRequestData(
                    requestData,
                    authenticatedUid,
                );

            attemptRef =
                db
                    .collection(
                        PAYMENT_ATTEMPTS_COLLECTION,
                    )
                    .doc();

            applicationReference =
                createApplicationReference(
                    authenticatedUid,
                    attemptRef.id,
                );

            const idempotencyKey =
                buildAqsIdempotencyKey({
                  userId:
                      authenticatedUid,

                  productCode:
                      input.productCode,

                  applicationReference:
                      applicationReference,

                  attempt:
                      1,
                });

            await attemptRef.set({
              attemptId:
                  attemptRef.id,

              userId:
                  authenticatedUid,

              appId:
                  "aqs_autoboq",

              productCode:
                  input.productCode,

              applicationReference:
                  applicationReference,

              provider:
                  input.provider,

              customerName:
                  input.customerName,

              customerEmail:
                  input.customerEmail,

              customerPhone:
                  input.customerPhone,

              idempotencyKey:
                  idempotencyKey,

              status:
                  "creating",

              stage:
                  "creating",

              quickLipaPaymentId:
                  null,

              quickLipaExternalId:
                  null,

              amount:
                  null,

              currency:
                  null,

              subscriptionActivated:
                  false,

              createdAt:
                  FieldValue
                      .serverTimestamp(),

              updatedAt:
                  FieldValue
                      .serverTimestamp(),
            });

            console.log(
                "AQS payment attempt created",
                {
                  attemptId:
                      attemptRef.id,

                  applicationReference:
                      applicationReference,

                  productCode:
                      input.productCode,
                },
            );

            const payment =
                await initiatePayment({
                  userId:
                      authenticatedUid,

                  attemptId:
                      attemptRef.id,

                  productCode:
                      input.productCode,

                  applicationReference:
                      applicationReference,

                  provider:
                      input.provider,

                  customer: {
                    id:
                        authenticatedUid,

                    name:
                        input.customerName,

                    email:
                        input.customerEmail,

                    phone:
                        input.customerPhone,
                  },

                  metadata: {
                    aqsAttemptId:
                        attemptRef.id,

                    purpose:
                        "subscription",

                    appId:
                        "aqs_autoboq",
                  },

                  idempotencyKey:
                      idempotencyKey,
                });

            console.log(
                "QuickLipa payment created",
                {
                  attemptId:
                      attemptRef.id,

                  paymentId:
                      payment.paymentId,

                  externalId:
                      payment.externalId,

                  status:
                      payment.status,

                  stage:
                      payment.stage,
                },
            );

            const normalizedStatus =
                readString(
                    payment.status,
                ).toLowerCase();

            let subscriptionId =
                null;

            /*
             * QuickLipa may already return
             * successful synchronously.
             */
            if (
              normalizedStatus ===
              "successful"
            ) {
              await db.runTransaction(
                  async (transaction) => {
                    /*
                     * READ 1
                     */
                    const freshAttemptSnapshot =
                        await transaction.get(
                            attemptRef,
                        );

                    if (
                      !freshAttemptSnapshot
                          .exists
                    ) {
                      throw new Error(
                          "Payment attempt no longer exists.",
                      );
                    }

                    const attemptData =
                        freshAttemptSnapshot
                            .data() ||
                        {};

                    /*
                     * Activation reads must
                     * happen before writes.
                     */
                    const subscriptionResult =
                        await activateSubscription({
                          transaction:
                              transaction,

                          userId:
                              authenticatedUid,

                          paymentPayload: {
                            paymentId:
                                payment
                                    .paymentId,

                            externalId:
                                payment
                                    .externalId,

                            productCode:
                                input
                                    .productCode,

                            amount:
                                payment
                                    .amount,

                            currency:
                                payment
                                    .currency,

                            provider:
                                payment
                                    .provider,

                            providerReference:
                                payment
                                    .providerReference,

                            providerMessage:
                                payment
                                    .providerMessage,

                            status:
                                "successful",
                          },

                          attemptData:
                              attemptData,
                        });

                    subscriptionId =
                        subscriptionResult
                            .subscriptionId ||
                        null;

                    /*
                     * WRITES START HERE
                     */
                    transaction.update(
                        attemptRef,
                        {
                          status:
                              "successful",

                          stage:
                              "completed",

                          quickLipaPaymentId:
                              payment
                                  .paymentId ||
                              null,

                          quickLipaExternalId:
                              payment
                                  .externalId ||
                              null,

                          paymentId:
                              payment
                                  .paymentId ||
                              null,

                          externalId:
                              payment
                                  .externalId ||
                              null,

                          providerReference:
                              payment
                                  .providerReference ||
                              null,

                          providerMessage:
                              payment
                                  .providerMessage ||
                              null,

                          amount:
                              payment
                                  .amount ||
                              null,

                          currency:
                              payment
                                  .currency ||
                              "TZS",

                          subscriptionId:
                              subscriptionId,

                          subscriptionActivated:
                              true,

                          subscriptionActivatedAt:
                              FieldValue
                                  .serverTimestamp(),

                          completedAt:
                              FieldValue
                                  .serverTimestamp(),

                          errorCode:
                              null,

                          errorMessage:
                              null,

                          updatedAt:
                              FieldValue
                                  .serverTimestamp(),
                        },
                    );
                  },
              );
            } else {
              /*
               * Pending / processing.
               * Webhook completes activation.
               */
              await attemptRef.update({
                status:
                    payment.status ||
                    "pending",

                stage:
                    payment.stage ||
                    "awaiting_callback",

                quickLipaPaymentId:
                    payment.paymentId ||
                    null,

                quickLipaExternalId:
                    payment.externalId ||
                    null,

                paymentId:
                    payment.paymentId ||
                    null,

                externalId:
                    payment.externalId ||
                    null,

                providerReference:
                    payment.providerReference ||
                    null,

                providerMessage:
                    payment.providerMessage ||
                    null,

                amount:
                    payment.amount ||
                    null,

                currency:
                    payment.currency ||
                    "TZS",

                errorCode:
                    null,

                errorMessage:
                    null,

                updatedAt:
                    FieldValue
                        .serverTimestamp(),
              });
            }

            return {
              success:
                  true,

              attemptId:
                  attemptRef.id,

              applicationReference:
                  applicationReference,

              paymentId:
                  payment.paymentId ||
                  "",

              externalId:
                  payment.externalId ||
                  "",

              status:
                  payment.status ||
                  "pending",

              stage:
                  payment.stage ||
                  "awaiting_callback",

              provider:
                  payment.provider ||
                  input.provider,

              providerReference:
                  payment.providerReference ||
                  null,

              providerMessage:
                  payment.providerMessage ||
                  null,

              productCode:
                  input.productCode,

              amount:
                  payment.amount ||
                  null,

              currency:
                  payment.currency ||
                  "TZS",

              subscriptionId:
                  subscriptionId,

              duplicate:
                  payment.duplicate ===
                  true,
            };
          } catch (error) {
            const normalizedFailure =
                normalizePaymentFailure(
                    error,
                );

            console.error(
                "initiateAqsPayment failed",
                {
                  name:
                      error &&
                      error.name ?
                        error.name :
                        null,

                  code:
                      error &&
                      error.code ?
                        error.code :
                        null,

                  status:
                      error &&
                      error.status ?
                        error.status :
                        null,

                  message:
                      error &&
                      error.message ?
                        error.message :
                        null,

                  details:
                      error &&
                      error.details ?
                        error.details :
                        null,

                  stack:
                      error &&
                      error.stack ?
                        error.stack :
                        null,
                },
            );

            if (attemptRef) {
              try {
                await attemptRef.set(
                    {
                      status:
                          "failed",

                      stage:
                          "initiation_failed",

                      errorCode:
                          normalizedFailure
                              .code,

                      integrationErrorCode:
                          error &&
                          error.code ?
                            error.code :
                            null,

                      errorMessage:
                          normalizedFailure
                              .message,

                      integrationErrorMessage:
                          error &&
                          error.message ?
                            error.message :
                            null,

                      failedAt:
                          FieldValue
                              .serverTimestamp(),

                      updatedAt:
                          FieldValue
                              .serverTimestamp(),
                    },
                    {
                      merge:
                          true,
                    },
                );
              } catch (saveError) {
                console.error(
                    "Could not save AQS payment failure",
                    {
                      message:
                          saveError &&
                          saveError.message ?
                            saveError.message :
                            null,
                    },
                );
              }
            }

            if (
              error instanceof
              HttpsError
            ) {
              throw error;
            }

            throw new HttpsError(
                normalizedFailure.status >=
                    500 ?
                  "unavailable" :
                  "failed-precondition",

                normalizedFailure.message,

                {
                  integrationCode:
                      normalizedFailure.code,

                  integrationStatus:
                      normalizedFailure.status,

                  attemptId:
                      attemptRef ?
                        attemptRef.id :
                        null,

                  applicationReference:
                      applicationReference ||
                      null,

                  integrationDetails:
                      error &&
                      error.details ?
                        error.details :
                        null,
                },
            );
          }
        },
    );

module.exports = {
  initiateAqsPayment,
};
