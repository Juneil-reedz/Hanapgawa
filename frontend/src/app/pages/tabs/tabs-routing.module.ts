import { NgModule } from '@angular/core';
import { RouterModule, Routes } from '@angular/router';

import { TabsPage } from './tabs.page';

const routes: Routes = [
  {
    path: '',
    component: TabsPage,
    children: [
      {
        path: 'discover',
        loadChildren: () => import('./discover/discover.module').then(m => m.DiscoverPageModule),
      },
      {
        path: 'bookings',
        loadChildren: () => import('./bookings/bookings.module').then(m => m.BookingsPageModule),
      },
      {
        path: 'jobs',
        loadChildren: () => import('./jobs/jobs.module').then(m => m.JobsPageModule),
      },
      {
        path: 'dashboard',
        loadChildren: () => import('./dashboard/dashboard.module').then(m => m.DashboardPageModule),
      },
      {
        path: 'profile',
        loadChildren: () => import('./profile/profile.module').then(m => m.ProfilePageModule),
      },
      {
        path: '',
        redirectTo: '/tabs/discover',
        pathMatch: 'full',
      },
    ],
  },
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
})
export class TabsPageRoutingModule {}
