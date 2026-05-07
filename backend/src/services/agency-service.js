const { HttpError } = require('../lib/http-error');
const {
  createOrRefreshApplication,
  findApplicationById,
  listAgencyApplicationsForUser,
  updateApplicationStatus,
} = require('../repositories/agency-worker-repository');
const { findUserById } = require('../repositories/user-repository');

async function applyWorkerToAgency({ agencyUserId, workerUserId, message }) {
  const worker = await findUserById(workerUserId);

  if (!worker || worker.role !== 'worker') {
    throw new HttpError(404, 'Worker account not found.');
  }

  return createOrRefreshApplication({ agencyUserId, workerUserId, message });
}

async function listMyApplications({ role, userId, status }) {
  return listAgencyApplicationsForUser({
    agencyUserId: role === 'agency' ? userId : undefined,
    workerUserId: role === 'worker' ? userId : undefined,
    status,
  });
}

async function resolveApplication({ applicationId, status, auth }) {
  const application = await findApplicationById(applicationId);

  if (!application) {
    throw new HttpError(404, 'Application not found.');
  }

  if (auth.role !== 'admin' && application.workerUserId !== auth.sub) {
    throw new HttpError(403, 'You can only manage applications sent to your worker account.');
  }

  return updateApplicationStatus({ id: application.id, status });
}

async function listAgencyMemberships(agencyUserId) {
  return listAgencyApplicationsForUser({ agencyUserId, status: 'approved' });
}

module.exports = { applyWorkerToAgency, listMyApplications, resolveApplication, listAgencyMemberships };
