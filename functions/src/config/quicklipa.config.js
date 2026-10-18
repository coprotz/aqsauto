const {
  defineSecret,
} = require(
    "firebase-functions/params",
);

const QUICKLIPA_API_KEY =
    defineSecret(
        "QUICKLIPA_API_KEY",
    );

const QUICKLIPA_APP_ID =
    defineSecret(
        "QUICKLIPA_APP_ID",
    );

const QUICKLIPA_BASE_URL =
    defineSecret(
        "QUICKLIPA_BASE_URL",
    );

const QUICKLIPA_WEBHOOK_SECRET =
    defineSecret(
        "QUICKLIPA_WEBHOOK_SECRET",
    );

module.exports = {
  QUICKLIPA_API_KEY,
  QUICKLIPA_APP_ID,
  QUICKLIPA_BASE_URL,
  QUICKLIPA_WEBHOOK_SECRET,
};
