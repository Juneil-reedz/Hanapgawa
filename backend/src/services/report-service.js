const { createReport, listReports, updateReportStatus } = require('../repositories/report-repository');

async function submitReport({ reporterUserId, providerUserId, bookingId, contentType, contentId, reason, details }) {
  return createReport({ reporterUserId, providerUserId, bookingId, contentType, contentId, reason, details });
}

async function getReports(status) {
  return listReports(status);
}

async function resolveReport({ id, status }) {
  return updateReportStatus(id, status);
}

module.exports = {
  getReports,
  resolveReport,
  submitReport,
};
