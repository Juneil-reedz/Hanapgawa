const { HttpError } = require('../lib/http-error');

function authorizeRoles(...allowedRoles) {
  return (req, _res, next) => {
    if (!req.auth) {
      return next(new HttpError(401, 'Authentication is required.'));
    }

    if (!allowedRoles.includes(req.auth.role)) {
      return next(new HttpError(403, 'You do not have permission to access this resource.'));
    }

    return next();
  };
}

module.exports = { authorizeRoles };
