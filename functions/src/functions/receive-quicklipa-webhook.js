const crypto = require("crypto");

const {
  onRequest,
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
  QUICKLIPA_WEBHOOK_SECRET,
} = require(
    "../config/quicklipa.config",
);

const {
  activateSubscription,
} = require(
    "../services/subscription-activation.service",
);

const PAYMENT_ATTEMPTS_COLLECTION =
    "payment-attempts";

const WEBHOOK_RECEIPTS_COLLECTION =
    "quicklipa-webhook-receipts";

/**
 * Read trimmed string.
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
 * Timing-safe string comparison.
 *
 * @param {string} left First value.
 * @param {string} right Second value.
 * @return {boolean}
 */
function safeEqual(
    left,
    right,
) {
  const leftBuffer =
      Buffer.from(
          readString(left),
      );

  const rightBuffer =
      Buffer.from(
          readString(right),
      );

  if (
    leftBuffer.length !==
    rightBuffer.length
  ) {
    return false;
  }

  return crypto.timingSafeEqual(
      leftBuffer,
      rightBuffer,
  );
}

/**
 * Verify QuickLipa HMAC signature.
 *
 * Expected signing input:
 *
 * timestamp.rawBody
 *
 * Expected header:
 *
 * X-QuickLipa-Signature
 *
 * @param {*} req HTTP request.
 * @return {Object}
 */
function verifyQuickLipaSignature(req) {
  const webhookSecret =
      QUICKLIPA_WEBHOOK_SECRET
          .value()
          .trim();

  if (!webhookSecret) {
    return {
      valid: false,
      reason:
          "missing_webhook_secret",
    };
  }

  const timestamp =
      readString(
          req.get(
              "X-QuickLipa-Timestamp",
          ),
      );

  const signature =
      readString(
          req.get(
              "X-QuickLipa-Signature",
          ),
      );

  if (
    !timestamp ||
    !signature
  ) {
    return {
      valid: false,
      reason:
          "missing_signature_headers",
    };
  }

  const timestampNumber =
      Number(timestamp);

  if (
    !Number.isFinite(
        timestampNumber,
    )
  ) {
    return {
      valid: false,
      reason:
          "invalid_timestamp",
    };
  }

  /*
   * Reject requests older than
   * 5 minutes.
   */
  const nowSeconds =
      Math.floor(
          Date.now() / 1000,
      );

  if (
    Math.abs(
        nowSeconds -
        timestampNumber,
    ) > 300
  ) {
    return {
      valid: false,
      reason:
          "expired_timestamp",
    };
  }

  if (!req.rawBody) {
    return {
      valid: false,
      reason:
          "missing_raw_body",
    };
  }

  const signedPayload =
      timestamp +
      "." +
      req.rawBody.toString(
          "utf8",
      );

  const expectedSignature =
      "sha256=" +
      crypto
          .createHmac(
              "sha256",
              webhookSecret,
          )
          .update(
              signedPayload,
          )
          .digest(
              "hex",
          );

  if (
    !safeEqual(
        signature,
        expectedSignature,
    )
  ) {
    return {
      valid: false,
      reason:
          "invalid_signature",
    };
  }

  return {
    valid: true,
  };
}

/**
 * Extract payment object from webhook body.
 *
 * Supports:
 *
 * {
 *   payment: {...}
 * }
 *
 * or direct payment fields.
 *
 * @param {*} body Webhook body.
 * @return {Object}
 */
function extractPayment(body) {
  if (
    body &&
    body.payment &&
    typeof body.payment ===
    "object"
  ) {
    return body.payment;
  }

  if (
    body &&
    typeof body === "object"
  ) {
    return body;
  }

  return {};
}

/**
 * Find AQS payment attempt.
 *
 * @param {*} db Firestore.
 * @param {Object} identifiers Payment identifiers.
 * @return {Promise<*>}
 */
async function findPaymentAttempt(
    db,
    identifiers,
) {
  const paymentId =
      readString(
          identifiers.paymentId,
      );

  const externalId =
      readString(
          identifiers.externalId,
      );

  const applicationReference =
      readString(
          identifiers.applicationReference,
      );

  /*
   * Prefer QuickLipa payment ID.
   */
  if (paymentId) {
    const snap =
        await db
            .collection(
                PAYMENT_ATTEMPTS_COLLECTION,
            )
            .where(
                "quickLipaPaymentId",
                "==",
                paymentId,
            )
            .limit(1)
            .get();

    if (!snap.empty) {
      return snap.docs[0];
    }

    /*
     * Compatibility with attempts
     * that may use paymentId.
     */
    const fallbackSnap =
        await db
            .collection(
                PAYMENT_ATTEMPTS_COLLECTION,
            )
            .where(
                "paymentId",
                "==",
                paymentId,
            )
            .limit(1)
            .get();

    if (!fallbackSnap.empty) {
      return fallbackSnap.docs[0];
    }
  }

  if (externalId) {
    const snap =
        await db
            .collection(
                PAYMENT_ATTEMPTS_COLLECTION,
            )
            .where(
                "quickLipaExternalId",
                "==",
                externalId,
            )
            .limit(1)
            .get();

    if (!snap.empty) {
      return snap.docs[0];
    }

    const fallbackSnap =
        await db
            .collection(
                PAYMENT_ATTEMPTS_COLLECTION,
            )
            .where(
                "externalId",
                "==",
                externalId,
            )
            .limit(1)
            .get();

    if (!fallbackSnap.empty) {
      return fallbackSnap.docs[0];
    }
  }

  if (applicationReference) {
    const snap =
        await db
            .collection(
                PAYMENT_ATTEMPTS_COLLECTION,
            )
            .where(
                "applicationReference",
                "==",
                applicationReference,
            )
            .limit(1)
            .get();

    if (!snap.empty) {
      return snap.docs[0];
    }
  }

  return null;
}

/**
 * Build deterministic webhook fingerprint.
 *
 * @param {Object} input Webhook values.
 * @return {string}
 */
function createWebhookFingerprint(input) {
  const eventId =
      readString(
          input.eventId,
      );

  if (eventId) {
    return crypto
        .createHash(
            "sha256",
        )
        .update(
            eventId,
        )
        .digest(
            "hex",
        );
  }

  const source =
      [
        readString(
            input.paymentId,
        ),
        readString(
            input.externalId,
        ),
        readString(
            input.applicationReference,
        ),
        readString(
            input.status,
        ),
        readString(
            input.stage,
        ),
      ].join("|");

  return crypto
      .createHash(
          "sha256",
      )
      .update(
          source,
      )
      .digest(
          "hex",
      );
}

/**
 * QuickLipa → AQS webhook.
 */
const receiveQuickLipaWebhook =
    onRequest(
        {
          region:
              "us-central1",

          secrets: [
            QUICKLIPA_WEBHOOK_SECRET,
          ],

          timeoutSeconds:
              120,

          memory:
              "256MiB",

          cors:
              false,
        },

        async (req, res) => {
          const db =
              getFirestore();

          try {
            /*
             * POST only.
             */
            if (
              req.method !==
              "POST"
            ) {
              res
                  .status(405)
                  .json({
                    success:
                        false,

                    error:
                        "method_not_allowed",
                  });

              return;
            }

            /*
             * 1. Verify signed webhook.
             */
            const verification =
                verifyQuickLipaSignature(
                    req,
                );

            if (!verification.valid) {
              console.warn(
                  "QuickLipa webhook rejected",
                  {
                    reason:
                        verification.reason,
                  },
              );

              res
                  .status(401)
                  .json({
                    success:
                        false,

                    error:
                        "invalid_webhook_signature",

                    reason:
                        verification.reason,
                  });

              return;
            }

            /*
             * 2. Read payload.
             */
            const body =
                req.body &&
                typeof req.body ===
                "object" ?
                  req.body :
                  {};

            const eventId =
                readString(
                    body.eventId,
                );

            const eventType =
                readString(
                    body.event ||
                    body.eventType ||
                    body.type,
                );

            const payment =
                extractPayment(
                    body,
                );

            const paymentId =
                readString(
                    payment.paymentId,
                );

            const externalId =
                readString(
                    payment.externalId,
                );

            const applicationReference =
                readString(
                    payment.applicationReference,
                );

            const productCode =
                readString(
                    payment.productCode,
                ).toUpperCase();

            const status =
                readString(
                    payment.status,
                ).toLowerCase();

            const stage =
                readString(
                    payment.stage,
                ).toLowerCase();

            const provider =
                readString(
                    payment.provider,
                );

            const providerReference =
                readString(
                    payment.providerReference,
                );

            const providerMessage =
                readString(
                    payment.providerMessage,
                );

            console.log(
                "QuickLipa webhook received",
                {
                  eventId:
                      eventId ||
                      null,

                  eventType:
                      eventType ||
                      null,

                  paymentId:
                      paymentId ||
                      null,

                  externalId:
                      externalId ||
                      null,

                  applicationReference:
                      applicationReference ||
                      null,

                  productCode:
                      productCode ||
                      null,

                  status:
                      status ||
                      null,

                  stage:
                      stage ||
                      null,
                },
            );

            if (
              !paymentId &&
              !externalId &&
              !applicationReference
            ) {
              res
                  .status(400)
                  .json({
                    success:
                        false,

                    error:
                        "payment_identifier_missing",
                  });

              return;
            }

            /*
             * 3. Find original AQS attempt.
             */
            const attemptSnapshot =
                await findPaymentAttempt(
                    db,
                    {
                      paymentId:
                          paymentId,

                      externalId:
                          externalId,

                      applicationReference:
                          applicationReference,
                    },
                );

            if (!attemptSnapshot) {
              console.error(
                  "AQS payment attempt not found",
                  {
                    paymentId:
                        paymentId ||
                        null,

                    externalId:
                        externalId ||
                        null,

                    applicationReference:
                        applicationReference ||
                        null,
                  },
              );

              res
                  .status(404)
                  .json({
                    success:
                        false,

                    error:
                        "payment_attempt_not_found",
                  });

              return;
            }

            const attemptRef =
                attemptSnapshot.ref;

            /*
             * 4. Idempotency fingerprint.
             */
            const fingerprint =
                createWebhookFingerprint({
                  eventId:
                      eventId,

                  paymentId:
                      paymentId,

                  externalId:
                      externalId,

                  applicationReference:
                      applicationReference,

                  status:
                      status,

                  stage:
                      stage,
                });

            const receiptRef =
                db
                    .collection(
                        WEBHOOK_RECEIPTS_COLLECTION,
                    )
                    .doc(
                        fingerprint,
                    );

            /*
             * 5. Determine webhook status.
             */
            const successful =
                status === "successful" ||
                status === "success" ||
                status === "completed" ||
                stage === "completed";

            const failed =
                status === "failed" ||
                status === "failure" ||
                status === "cancelled" ||
                status === "canceled" ||
                stage === "failed";

            let subscriptionId =
                null;

            let duplicate =
                false;

            /*
             * 6. Process transaction.
             */
            await db.runTransaction(
                async (transaction) => {
                  /*
                   * ALL READS FIRST.
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

                  const receiptSnapshot =
                      await transaction.get(
                          receiptRef,
                      );

                  if (
                    receiptSnapshot.exists
                  ) {
                    duplicate =
                        true;

                    const existingReceipt =
                        receiptSnapshot
                            .data() ||
                        {};

                    subscriptionId =
                        readString(
                            existingReceipt
                                .subscriptionId,
                        ) ||
                        null;

                    return;
                  }

                  const attemptData =
                      freshAttemptSnapshot
                          .data() ||
                      {};

                  /*
                   * Preserve already successful
                   * payment state.
                   */
                  const currentStatus =
                      readString(
                          attemptData.status,
                      ).toLowerCase();

                  const alreadySuccessful =
                      currentStatus ===
                          "successful" ||
                      currentStatus ===
                          "completed";

                  /*
                   * If webhook is successful,
                   * activate subscription BEFORE
                   * any transaction writes.
                   */
                  let activationResult =
                      null;

                  if (successful) {
                    activationResult =
                        await activateSubscription({
                          transaction:
                              transaction,

                          userId:
                              readString(
                                  attemptData.userId,
                              ),

                          paymentPayload: {
                            paymentId:
                                paymentId ||
                                readString(
                                    attemptData
                                        .quickLipaPaymentId,
                                ) ||
                                readString(
                                    attemptData
                                        .paymentId,
                                ),

                            externalId:
                                externalId ||
                                readString(
                                    attemptData
                                        .quickLipaExternalId,
                                ) ||
                                readString(
                                    attemptData
                                        .externalId,
                                ),

                            productCode:
                                productCode ||
                                readString(
                                    attemptData
                                        .productCode,
                                ),

                            amount:
                                payment.amount !==
                                undefined ?
                                  payment.amount :
                                  attemptData.amount,

                            currency:
                                readString(
                                    payment.currency,
                                ) ||
                                readString(
                                    attemptData.currency,
                                ) ||
                                "TZS",

                            provider:
                                provider ||
                                readString(
                                    attemptData.provider,
                                ),

                            providerReference:
                                providerReference ||
                                readString(
                                    attemptData
                                        .providerReference,
                                ),

                            providerMessage:
                                providerMessage ||
                                readString(
                                    attemptData
                                        .providerMessage,
                                ),

                            status:
                                "successful",
                          },

                          attemptData:
                              attemptData,
                        });

                    subscriptionId =
                        activationResult
                            .subscriptionId ||
                        null;
                  }

                  /*
                   * WRITES START HERE.
                   */

                  const finalStatus =
                      alreadySuccessful ?
                        "successful" :
                        successful ?
                          "successful" :
                          failed ?
                            "failed" :
                            status ||
                            "pending";

                  const finalStage =
                      alreadySuccessful ?
                        "completed" :
                        successful ?
                          "completed" :
                          failed ?
                            "failed" :
                            stage ||
                            "awaiting_callback";

                  transaction.update(
                      attemptRef,
                      {
                        status:
                            finalStatus,

                        stage:
                            finalStage,

                        quickLipaPaymentId:
                            paymentId ||
                            attemptData
                                .quickLipaPaymentId ||
                            attemptData
                                .paymentId ||
                            null,

                        quickLipaExternalId:
                            externalId ||
                            attemptData
                                .quickLipaExternalId ||
                            attemptData
                                .externalId ||
                            null,

                        paymentId:
                            paymentId ||
                            attemptData
                                .paymentId ||
                            null,

                        externalId:
                            externalId ||
                            attemptData
                                .externalId ||
                            null,

                        provider:
                            provider ||
                            attemptData
                                .provider ||
                            null,

                        providerReference:
                            providerReference ||
                            attemptData
                                .providerReference ||
                            null,

                        providerMessage:
                            providerMessage ||
                            attemptData
                                .providerMessage ||
                            null,

                        productCode:
                            productCode ||
                            attemptData
                                .productCode ||
                            null,

                        amount:
                            payment.amount !==
                            undefined ?
                              payment.amount :
                              attemptData.amount ||
                              null,

                        currency:
                            readString(
                                payment.currency,
                            ) ||
                            attemptData
                                .currency ||
                            "TZS",

                        subscriptionId:
                            subscriptionId ||
                            attemptData
                                .subscriptionId ||
                            null,

                        subscriptionActivated:
                            successful ?
                              true :
                              attemptData
                                  .subscriptionActivated ===
                                  true,

                        subscriptionActivatedAt:
                            successful ?
                              FieldValue
                                  .serverTimestamp() :
                              attemptData
                                  .subscriptionActivatedAt ||
                              null,

                        webhookEventId:
                            eventId ||
                            null,

                        webhookEventType:
                            eventType ||
                            null,

                        webhookReceivedAt:
                            FieldValue
                                .serverTimestamp(),

                        completedAt:
                            successful ?
                              FieldValue
                                  .serverTimestamp() :
                              attemptData
                                  .completedAt ||
                              null,

                        failedAt:
                            failed ?
                              FieldValue
                                  .serverTimestamp() :
                              attemptData
                                  .failedAt ||
                              null,

                        errorCode:
                            failed ?
                              "payment_failed" :
                              null,

                        errorMessage:
                            failed ?
                              providerMessage ||
                              "Payment failed." :
                              null,

                        updatedAt:
                            FieldValue
                                .serverTimestamp(),
                      },
                  );

                  transaction.set(
                      receiptRef,
                      {
                        fingerprint:
                            fingerprint,

                        eventId:
                            eventId ||
                            null,

                        eventType:
                            eventType ||
                            null,

                        attemptId:
                            attemptSnapshot.id,

                        userId:
                            readString(
                                attemptData.userId,
                            ) ||
                            null,

                        paymentId:
                            paymentId ||
                            null,

                        externalId:
                            externalId ||
                            null,

                        applicationReference:
                            applicationReference ||
                            readString(
                                attemptData
                                    .applicationReference,
                            ) ||
                            null,

                        productCode:
                            productCode ||
                            readString(
                                attemptData
                                    .productCode,
                            ) ||
                            null,

                        status:
                            status ||
                            null,

                        stage:
                            stage ||
                            null,

                        subscriptionId:
                            subscriptionId ||
                            null,

                        successful:
                            successful,

                        failed:
                            failed,

                        receivedAt:
                            FieldValue
                                .serverTimestamp(),
                      },
                  );
                },
            );

            /*
             * Duplicate webhook is still
             * acknowledged with HTTP 200.
             */
            res
                .status(200)
                .json({
                  success:
                      true,

                  received:
                      true,

                  duplicate:
                      duplicate,

                  attemptId:
                      attemptSnapshot.id,

                  subscriptionId:
                      subscriptionId,
                });
          } catch (error) {
            console.error(
                "receiveQuickLipaWebhook error",
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

                  message:
                      error &&
                      error.message ?
                        error.message :
                        null,

                  stack:
                      error &&
                      error.stack ?
                        error.stack :
                        null,
                },
            );

            res
                .status(500)
                .json({
                  success:
                      false,

                  error:
                      "webhook_processing_failed",
                });
          }
        },
    );

module.exports = {
  receiveQuickLipaWebhook,
};
