import { HttpErrorResponse } from '@angular/common/http';
import { Component } from '@angular/core';
import { Router } from '@angular/router';

import { AuthResponse, MarketplaceApiService, RegisterResponse } from '../../services/marketplace-api.service';

@Component({
  selector: 'app-auth',
  templateUrl: 'auth.page.html',
  styleUrls: ['auth.page.scss'],
  standalone: false,
})
export class AuthPage {
  mode: 'login' | 'register' | 'verify' = 'login';
  loading = false;
  message = '';
  messageIsError = false;

  form = {
    fullName: '',
    email: '',
    password: '',
    verificationCode: '',
  };

  constructor(private readonly api: MarketplaceApiService, private readonly router: Router) {}

  switchMode(mode: 'login' | 'register'): void {
    this.mode = mode;
    this.message = '';
  }

  fillDemo(role: 'client' | 'worker' | 'agency'): void {
    this.mode = 'login';
    this.form.email = `${role}@hanapgawa.demo`;
    this.form.password = 'Password123!';
    this.message = '';
  }

  submit(): void {
    if (this.mode === 'verify') {
      this.verifyEmail();
      return;
    }

    if (!this.form.email || !this.form.password) {
      this.messageIsError = true;
      this.message = 'Please enter your email and password.';
      return;
    }

    this.loading = true;
    this.message = '';

    if (this.mode === 'login') {
      this.api.login({ email: this.form.email, password: this.form.password }).subscribe({
        next: (res) => this.onSuccess(res),
        error: (err: HttpErrorResponse) => this.onError(err),
      });
      return;
    }

    this.api.register({
      email: this.form.email,
      password: this.form.password,
      fullName: this.form.fullName,
    }).subscribe({
      next: (res) => this.onRegistered(res),
      error: (err: HttpErrorResponse) => this.onError(err),
    });
  }

  resendCode(): void {
    if (!this.form.email) {
      this.messageIsError = true;
      this.message = 'Email is required before requesting a new code.';
      return;
    }

    this.loading = true;
    this.api.resendVerificationCode({ email: this.form.email }).subscribe({
      next: (res) => {
        this.loading = false;
        this.messageIsError = false;
        this.message = res.devVerificationCode
          ? `New verification code: ${res.devVerificationCode}`
          : 'A new verification code was sent to your email.';
      },
      error: (err: HttpErrorResponse) => this.onError(err),
    });
  }

  private verifyEmail(): void {
    if (!this.form.email || !this.form.verificationCode) {
      this.messageIsError = true;
      this.message = 'Enter your email and verification code.';
      return;
    }

    this.loading = true;
    this.message = '';

    this.api.verifyEmail({ email: this.form.email, code: this.form.verificationCode }).subscribe({
      next: (res) => this.onSuccess(res),
      error: (err: HttpErrorResponse) => this.onError(err),
    });
  }

  private onRegistered(res: RegisterResponse): void {
    this.mode = 'verify';
    this.loading = false;
    this.messageIsError = false;
    this.message = res.devVerificationCode
      ? `Account created. Development verification code: ${res.devVerificationCode}`
      : 'Account created. Check your email for the verification code.';
  }

  private onSuccess(res: AuthResponse): void {
    this.api.persistSession(res);
    this.loading = false;
    this.router.navigate(['/tabs/discover'], { replaceUrl: true });
  }

  private onError(err: HttpErrorResponse): void {
    this.loading = false;
    this.messageIsError = true;
    this.message = err.error?.error?.message || 'Something went wrong. Please try again.';
  }
}
