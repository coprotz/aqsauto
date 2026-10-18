const {
  getFirestore,
  FieldValue,
  Timestamp,
} = require(
    "firebase-admin/firestore",
);

function getDb() {
  return getFirestore();
}


/*
 * AQS subscription products.
 *
 * QuickLipa remains the trusted source
 * of the payment amount.
 */
const PRODUCT_PLANS = {
  AQS_BASIC_MONTHLY: {
    planId: "basic",
    planName: "Basic",
    billingCycle: "monthly",
    durationMonths: 1,
    projectLimit: 2,
    userLimit: 1,
  },

  AQS_BASIC_YEARLY: {
    planId: "basic",
    planName: "Basic",
    billingCycle: "yearly",
    durationMonths: 12,
    projectLimit: 2,
    userLimit: 1,
  },

  AQS_PRO_MONTHLY: {
    planId: "pro",
    planName: "Pro",
    billingCycle: "monthly",
    durationMonths: 1,
    projectLimit: 25,
    userLimit: 1,
  },

  AQS_PRO_YEARLY: {
    planId: "pro",
    planName: "Pro",
    billingCycle: "yearly",
    durationMonths: 12,
    projectLimit: 25,
    userLimit: 1,
  },

  AQS_BUSINESS_MONTHLY: {
    planId: "business",
    planName: "Business",
    billingCycle: "monthly",
    durationMonths: 1,
    projectLimit: 100,
    userLimit: 5,
  },

  AQS_BUSINESS_YEARLY: {
    planId: "business",
    planName: "Business",
    billingCycle: "yearly",
    durationMonths: 12,
    projectLimit: 100,
    userLimit: 5,
  },
};

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
 * Reads a numeric value.
 *
 * @param {*} value Raw value.
 * @return {number|null}
 */
function readNumber(value) {
  if (
    typeof value === "number" &&
    Number.isFinite(value)
  ) {
    return value;
  }

  const parsed =
      Number(value);

  if (
    Number.isFinite(parsed)
  ) {
    return parsed;
  }

  return null;
}

/**
 * Converts supported date values to Date.
 *
 * @param {*} value Raw value.
 * @return {Date|null}
 */
function readDate(value) {
  if (!value) {
    return null;
  }

  if (
    value instanceof Date
  ) {
    return value;
  }

  if (
    value &&
    typeof value.toDate === "function"
  ) {
    return value.toDate();
  }

  if (
    typeof value === "string"
  ) {
    const parsed =
        new Date(value);

    if (
      !Number.isNaN(
          parsed.getTime(),
      )
    ) {
      return parsed;
    }
  }

  return null;
}

/**
 * Adds calendar months to a date.
 *
 * @param {Date} date Start date.
 * @param {number} months Number of months.
 * @return {Date}
 */
function addMonths(
    date,
    months,
) {
  const result =
      new Date(
          date.getTime(),
      );

  const originalDay =
      result.getUTCDate();

  /*
   * Move to day 1 first so dates such as
   * 31 January do not accidentally jump
   * over February.
   */
  result.setUTCDate(1);

  result.setUTCMonth(
      result.getUTCMonth() +
      months,
  );

  /*
   * Find last valid day of target month.
   */
  const lastDay =
      new Date(
          Date.UTC(
              result.getUTCFullYear(),
              result.getUTCMonth() + 1,
              0,
          ),
      ).getUTCDate();

  result.setUTCDate(
      Math.min(
          originalDay,
          lastDay,
      ),
  );

  return result;
}

/**
 * Creates a Firestore-safe subscription ID.
 *
 * Payment ID is preferred because it gives
 * us deterministic idempotency.
 *
 * @param {Object} paymentPayload Payment data.
 * @param {Object} attemptData Attempt data.
 * @return {string}
 */
function createSubscriptionId(
    paymentPayload,
    attemptData,
) {
  const paymentId =
      readString(
          paymentPayload &&
          paymentPayload.paymentId,
      );

  const externalId =
      readString(
          paymentPayload &&
          paymentPayload.externalId,
      );

  const attemptId =
      readString(
          attemptData &&
          attemptData.attemptId,
      );

  const raw =
      paymentId ||
      externalId ||
      attemptId;

  if (!raw) {
    throw new Error(
        "Cannot create subscription ID without payment identifier.",
    );
  }

  return raw
      .replace(
          /[^A-Za-z0-9_-]/g,
          "-",
      )
      .slice(0, 120);
}

/**
 * Activates an AQS subscription.
 *
 * IMPORTANT:
 *
 * This function runs inside an existing
 * Firestore transaction.
 *
 * It performs its reads before its writes.
 *
 * @param {Object} input Activation input.
 * @param {FirebaseFirestore.Transaction} input.transaction Firestore transaction.
 * @param {string} input.userId Firebase UID.
 * @param {Object} input.paymentPayload Trusted QuickLipa payment.
 * @param {Object} input.attemptData Existing payment attempt.
 * @return {Promise<Object>}
 */
async function activateSubscription(input) {
  const transaction =
      input &&
      input.transaction ?
        input.transaction :
        null;

  const userId =
      readString(
          input &&
          input.userId,
      );

  const paymentPayload =
      input &&
      input.paymentPayload &&
      typeof input.paymentPayload === "object" ?
        input.paymentPayload :
        {};

  const attemptData =
      input &&
      input.attemptData &&
      typeof input.attemptData === "object" ?
        input.attemptData :
        {};

  if (!transaction) {
    throw new Error(
        "Firestore transaction is required.",
    );
  }

  if (!userId) {
    throw new Error(
        "User ID is required for subscription activation.",
    );
  }

  const db = getDb();

  const paymentStatus =
      readString(
          paymentPayload.status,
      ).toLowerCase();

  if (
    paymentStatus !== "successful" &&
    paymentStatus !== "success" &&
    paymentStatus !== "completed"
  ) {
    throw new Error(
        "Only successful payments can activate a subscription.",
    );
  }

  const productCode =
      readString(
          paymentPayload.productCode ||
          attemptData.productCode,
      ).toUpperCase();

  const plan =
      PRODUCT_PLANS[
          productCode
      ];

  if (!plan) {
    throw new Error(
        "Unsupported AQS subscription product: " +
        productCode,
    );
  }

  const paymentId =
      readString(
          paymentPayload.paymentId,
      );

  const externalId =
      readString(
          paymentPayload.externalId,
      );

  const subscriptionId =
      createSubscriptionId(
          paymentPayload,
          attemptData,
      );

  const userRef =
      db
          .collection("users")
          .doc(userId);

  const subscriptionRef =
      userRef
          .collection("subscriptions")
          .doc(subscriptionId);

  /*
   * READ 1:
   * Current user subscription summary.
   */
  const userSnapshot =
      await transaction.get(
          userRef,
      );

  /*
   * READ 2:
   * Deterministic subscription document.
   *
   * If it already exists, this payment
   * was previously activated.
   */
  const subscriptionSnapshot =
      await transaction.get(
          subscriptionRef,
      );

  const userData =
      userSnapshot.exists ?
        userSnapshot.data() || {} :
        {};

  /*
   * IDEMPOTENCY
   *
   * Same QuickLipa payment cannot create
   * the subscription twice.
   */
  if (
    subscriptionSnapshot.exists
  ) {
    const existingSubscription =
        subscriptionSnapshot.data() ||
        {};

    return {
      activated: false,
      duplicate: true,

      subscriptionId:
          subscriptionId,

      planId:
          readString(
              existingSubscription.planId,
          ) ||
          plan.planId,

      planName:
          readString(
              existingSubscription.planName,
          ) ||
          plan.planName,

      billingCycle:
          readString(
              existingSubscription.billingCycle,
          ) ||
          plan.billingCycle,

      productCode:
          productCode,
    };
  }

  /*
   * Establish subscription dates.
   */
  const now =
      new Date();

  let startsAt =
      now;

  const existingStatus =
      readString(
          userData.subscriptionStatus,
      ).toLowerCase();

  const existingProductCode =
      readString(
          userData.subscriptionProductCode,
      ).toUpperCase();

  const existingExpiry =
      readDate(
          userData.subscriptionExpiresAt,
      );

  /*
   * Same exact product renewal:
   *
   * Pro Monthly active until future date
   * + another Pro Monthly payment
   * => extend from existing expiry.
   */
  const sameProduct =
      existingProductCode ===
      productCode;

  const existingStillActive =
      existingStatus === "active" &&
      existingExpiry &&
      existingExpiry.getTime() >
      now.getTime();

  if (
    sameProduct &&
    existingStillActive
  ) {
    startsAt =
        existingExpiry;
  }

  /*
   * Different plan or billing-cycle change:
   *
   * Starts immediately.
   *
   * We are NOT implementing proration in
   * this version yet.
   */
  const expiresAt =
      addMonths(
          startsAt,
          plan.durationMonths,
      );

  const amount =
      readNumber(
          paymentPayload.amount,
      );

  const currency =
      readString(
          paymentPayload.currency,
      ) ||
      "TZS";

  const provider =
      readString(
          paymentPayload.provider ||
          attemptData.provider,
      );

  const providerReference =
      readString(
          paymentPayload.providerReference,
      );

  const providerMessage =
      readString(
          paymentPayload.providerMessage,
      );

  const applicationReference =
      readString(
          attemptData.applicationReference,
      );

  const attemptId =
      readString(
          attemptData.attemptId,
      );

  /*
   * -----------------------------------
   * WRITES START HERE
   * -----------------------------------
   *
   * Do not add transaction.get()
   * below this point.
   */

  transaction.set(
      subscriptionRef,
      {
        subscriptionId:
            subscriptionId,

        userId:
            userId,

        appId:
            "aqs_autoboq",

        planId:
            plan.planId,

        planName:
            plan.planName,

        productCode:
            productCode,

        billingCycle:
            plan.billingCycle,

        durationMonths:
            plan.durationMonths,

        status:
            "active",

        projectLimit:
            plan.projectLimit,

        userLimit:
            plan.userLimit,

        amountPaid:
            amount,

        currency:
            currency,

        paymentId:
            paymentId ||
            null,

        externalId:
            externalId ||
            null,

        paymentAttemptId:
            attemptId ||
            null,

        applicationReference:
            applicationReference ||
            null,

        provider:
            provider ||
            null,

        providerReference:
            providerReference ||
            null,

        providerMessage:
            providerMessage ||
            null,

        startedAt:
            Timestamp.fromDate(
                startsAt,
            ),

        expiresAt:
            Timestamp.fromDate(
                expiresAt,
            ),

        createdAt:
            FieldValue.serverTimestamp(),

        updatedAt:
            FieldValue.serverTimestamp(),
      },
  );

  /*
   * Current-subscription summary.
   *
   * Flutter reads this document live.
   */
  transaction.set(
      userRef,
      {
        subscriptionId:
            subscriptionId,

        subscriptionStatus:
            "active",

        subscriptionPlanId:
            plan.planId,

        subscriptionPlanName:
            plan.planName,

        subscriptionProductCode:
            productCode,

        subscriptionBillingCycle:
            plan.billingCycle,

        subscriptionAmountPaid:
            amount,

        subscriptionCurrency:
            currency,

        subscriptionProjectLimit:
            plan.projectLimit,

        subscriptionUserLimit:
            plan.userLimit,

        subscriptionStartedAt:
            Timestamp.fromDate(
                startsAt,
            ),

        subscriptionExpiresAt:
            Timestamp.fromDate(
                expiresAt,
            ),

        subscriptionPaymentId:
            paymentId ||
            null,

        subscriptionExternalId:
            externalId ||
            null,

        subscriptionProvider:
            provider ||
            null,

        subscriptionProviderReference:
            providerReference ||
            null,

        subscriptionUpdatedAt:
            FieldValue.serverTimestamp(),
      },
      {
        merge: true,
      },
  );

  return {
    activated: true,
    duplicate: false,

    subscriptionId:
        subscriptionId,

    planId:
        plan.planId,

    planName:
        plan.planName,

    productCode:
        productCode,

    billingCycle:
        plan.billingCycle,

    projectLimit:
        plan.projectLimit,

    userLimit:
        plan.userLimit,

    startedAt:
        startsAt.toISOString(),

    expiresAt:
        expiresAt.toISOString(),

    paymentId:
        paymentId ||
        null,

    externalId:
        externalId ||
        null,
  };
}

module.exports = {
  activateSubscription,
};
