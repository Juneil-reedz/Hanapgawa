import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';

import { JobOffer, JobPost, MarketplaceApiService, PublicUserProfile } from '../../../services/marketplace-api.service';

@Component({
  selector: 'app-jobs',
  templateUrl: 'jobs.page.html',
  styleUrls: ['jobs.page.scss'],
  standalone: false,
})
export class JobsPage implements OnInit {
  jobs: JobPost[] = [];
  selectedJob: JobPost | null = null;
  selectedJobOffers: JobOffer[] = [];
  selectedUserProfile: PublicUserProfile | null = null;
  showJobForm = false;
  loading = false;
  message = '';
  success = false;
  savingJob = false;
  sendingOffer = false;
  acceptingOfferId = '';

  municipalities = ['Bongao', 'Simunul', 'Sitangkai', 'Panglima Sugala', 'Turtle Islands'];

  jobForm = {
    postType: 'seeking_worker' as 'seeking_worker' | 'seeking_client',
    title: '',
    category: 'Carpentry',
    municipality: 'Bongao',
    locationDetails: '',
    description: '',
    budgetMin: 500,
    budgetMax: 2500,
    scheduledAt: '',
  };

  offerForm = {
    message: 'I can help with this job. I am available to discuss details.',
    proposedPrice: 1000,
    media: [] as Array<{ imageUrl: string; caption?: string }>,
  };

  constructor(private readonly api: MarketplaceApiService, private readonly router: Router) {}

  get token(): string {
    return this.api.getToken();
  }

  get currentUser() {
    return this.api.getStoredUser();
  }

  ngOnInit(): void {
    this.loadJobs();
  }

  loadJobs(): void {
    this.loading = true;
    this.message = '';

    this.api.getJobs(this.token).subscribe({
      next: (res) => {
        this.loading = false;
        this.jobs = res.jobs;
      },
      error: (err: HttpErrorResponse) => {
        this.loading = false;
        this.success = false;
        this.message = err.error?.error?.message || 'Could not load jobs.';
      },
    });
  }

  openJobForm(): void {
    this.showJobForm = true;
    this.message = '';
  }

  closeJobForm(): void {
    this.showJobForm = false;
  }

  createJob(): void {
    this.savingJob = true;
    this.message = '';

    this.api.createJobPost({
      ...this.jobForm,
      budgetMin: Number(this.jobForm.budgetMin) || undefined,
      budgetMax: Number(this.jobForm.budgetMax) || undefined,
      scheduledAt: this.jobForm.scheduledAt ? new Date(this.jobForm.scheduledAt).toISOString() : undefined,
    }, this.token).subscribe({
      next: () => {
        this.savingJob = false;
        this.success = true;
        this.message = this.jobForm.postType === 'seeking_worker'
          ? 'Post published. Workers can now respond.'
          : 'Post published. Clients can now contact you.';
        this.jobForm = { postType: 'seeking_worker', title: '', category: 'Carpentry', municipality: 'Bongao', locationDetails: '', description: '', budgetMin: 500, budgetMax: 2500, scheduledAt: '' };
        this.closeJobForm();
        this.loadJobs();
      },
      error: (err: HttpErrorResponse) => {
        this.savingJob = false;
        this.success = false;
        this.message = err.error?.error?.message || 'Could not post job.';
      },
    });
  }

  openJob(job: JobPost): void {
    this.selectedJob = job;
    this.selectedJobOffers = [];
    this.message = '';

    this.api.getJobDetail(job.id, this.token).subscribe({
      next: (res) => {
        this.selectedJob = res.jobPost;
        this.selectedJobOffers = res.offers;
      },
      error: (err: HttpErrorResponse) => {
        this.success = false;
        this.message = err.error?.error?.message || 'Could not load job details.';
      },
    });
  }

  closeJob(): void {
    this.selectedJob = null;
    this.selectedJobOffers = [];
    this.message = '';
  }

  sendOffer(): void {
    if (!this.selectedJob) return;

    this.sendingOffer = true;
    this.message = '';

    this.api.sendJobOffer(this.selectedJob.id, {
      message: this.offerForm.message,
      proposedPrice: Number(this.offerForm.proposedPrice) || undefined,
      media: this.offerForm.media,
    }, this.token).subscribe({
      next: () => {
        this.sendingOffer = false;
        this.success = true;
        this.message = this.selectedJob?.postType === 'seeking_worker' ? 'Response sent to the customer.' : 'Response sent to the worker.';
        this.offerForm.media = [];
        this.loadJobs();
        this.openJob(this.selectedJob as JobPost);
      },
      error: (err: HttpErrorResponse) => {
        this.sendingOffer = false;
        this.success = false;
        this.message = err.error?.error?.message || 'Could not send offer.';
      },
    });
  }

  acceptOffer(offer: JobOffer): void {
    if (!this.selectedJob) return;

    this.acceptingOfferId = offer.id;
    this.message = '';

    this.api.acceptJobOffer(this.selectedJob.id, offer.id, this.token).subscribe({
      next: (res) => {
        this.acceptingOfferId = '';
        this.success = true;
        this.message = 'Offer accepted. A booking was created.';
        this.loadJobs();
        this.openJob(res.jobPost);
      },
      error: (err: HttpErrorResponse) => {
        this.acceptingOfferId = '';
        this.success = false;
        this.message = err.error?.error?.message || 'Could not accept offer.';
      },
    });
  }

  openBooking(): void {
    this.router.navigate(['/tabs/bookings']);
  }

  openProviderProfile(providerUserId: string): void {
    this.closeJob();
    this.router.navigate(['/tabs/discover/provider', providerUserId]);
  }

  openClientProfile(clientUserId: string): void {
    this.api.getPublicUserProfile(clientUserId, this.token).subscribe({
      next: (res) => {
        this.selectedUserProfile = res.user;
      },
      error: (err: HttpErrorResponse) => {
        this.success = false;
        this.message = err.error?.error?.message || 'Could not load client profile.';
      },
    });
  }

  closeUserProfile(): void {
    this.selectedUserProfile = null;
  }

  onOfferPhotoSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = () => {
      this.offerForm.media = [{ imageUrl: String(reader.result), caption: file.name }];
    };
    reader.readAsDataURL(file);
    input.value = '';
  }

  removeOfferPhoto(): void {
    this.offerForm.media = [];
  }

  formatDate(value: string): string {
    return new Date(value).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' });
  }

  formatSchedule(value?: string): string {
    if (!value) return 'No schedule set';
    return new Date(value).toLocaleString('en-PH', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
  }

  postTypeLabel(post: JobPost): string {
    return post.postType === 'seeking_worker' ? 'Looking for worker' : 'Looking for client';
  }

  postTypeBadgeColor(post: JobPost): string {
    return post.postType === 'seeking_worker' ? 'primary' : 'tertiary';
  }

  postTypeClass(post: JobPost): string {
    return post.postType === 'seeking_worker' ? 'seeking-worker' : 'seeking-client';
  }

  canRespondToSelectedJob(): boolean {
    return Boolean(this.selectedJob && this.selectedJob.status === 'open' && this.selectedJob.clientUserId !== this.currentUser?.id);
  }

  canManageSelectedJob(): boolean {
    return Boolean(this.selectedJob && (this.selectedJob.clientUserId === this.currentUser?.id || this.currentUser?.role === 'admin'));
  }

  trackJob(_i: number, job: JobPost): string {
    return job.id;
  }

  trackOffer(_i: number, offer: JobOffer): string {
    return offer.id;
  }
}
