const { HttpError } = require('./http-error');

function isApprovedProvider(user) {
  return Boolean(user) && ['worker', 'agency'].includes(user.role) && user.status === 'approved';
}

function assertApprovedProvider(user, message = 'Provider account is not approved.') {
  if (!isApprovedProvider(user)) {
    throw new HttpError(403, message);
  }
}

module.exports = {
  assertApprovedProvider,
  isApprovedProvider,
};
