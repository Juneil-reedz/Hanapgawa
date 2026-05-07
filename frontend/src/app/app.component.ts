import { Component, OnInit } from '@angular/core';

import { NetworkSyncService } from './services/network-sync.service';

@Component({
  selector: 'app-root',
  templateUrl: 'app.component.html',
  styleUrls: ['app.component.scss'],
  standalone: false,
})
export class AppComponent implements OnInit {
  constructor(private readonly networkSync: NetworkSyncService) {}

  ngOnInit(): void {
    this.networkSync.start();
  }
}
