# Selected matched results

1280 x 800, 20 warmups, 100 samples, milliseconds. All GL frames clear and wait for completion. The same cached shadow is used by the first four cases.

| Boards | Case | p50 ms | p95 ms |
|---:|---|---:|---:|
| 1 | SW sparse, cached shadow | 1.1042 | 1.2490 |
| 1 | SW forced full, cached shadow | 15.9367 | 16.9501 |
| 1 | SW sparse + full upload | 3.2955 | 4.1423 |
| 1 | GL retained, cached shadow | 4.0609 | 4.4870 |
| 1 | SW sparse, live bounded shadow | 3.3260 | 4.3034 |
| 64 | SW sparse, cached shadow | 0.4229 | 0.6176 |
| 64 | SW forced full, cached shadow | 17.6138 | 18.8102 |
| 64 | SW sparse + full upload | 2.4090 | 3.6389 |
| 64 | GL retained, cached shadow | 9.1428 | 9.9949 |
| 64 | SW sparse, live bounded shadow | 3.5427 | 3.9963 |
