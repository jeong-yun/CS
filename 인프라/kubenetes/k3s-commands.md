# 쿠버네티스(k3s) 명령어 모음집

k3s 환경 기준으로 정리했습니다. 일반 쿠버네티스에서도 `kubectl` 명령은 동일하게 쓸 수 있습니다.

---

## 0. 플레이스홀더와 기본 설정

| 표기 | 의미 |
|---|---|
| `<NS>` | 네임스페이스 |
| `<POD>` | 파드명 (예: `<앱이름>-<해시>-<해시>` 형태) |
| `<DEPLOY>` | 디플로이먼트명 |
| `<CONTAINER>` | 파드 안 컨테이너명 (컨테이너가 여러 개일 때) |
| `<POD_UID>` | 파드 UID (`/var/lib/kubelet/pods/` 아래 디렉터리명) |
| `<NODE>` | 노드명 |
| `<K3S_ROOT>` | k3s 데이터 경로 (기본 `/var/lib/rancher/k3s`) |

### k3s에서 kubectl 실행

```bash
sudo k3s kubectl get pods -A                     # k3s 내장 kubectl(환경에 따라 command not found)
sudo /usr/local/bin/k3s kubectl get pods -A      # PATH에 없을 때 전체 경로
kubectl get pods -A                              # kubectl이 설정된 경우
```

**`sudo k3s`가 `command not found`일 때**

k3s 바이너리는 보통 `/usr/local/bin`에 있는데, `sudo`는 `secure_path`로 PATH를 재설정하므로 이 경로가 빠져 있으면 실패합니다. 절대경로나 변수로 실행하세요.

```bash
which k3s                                  # 위치 확인
K3S=$(which k3s)                           # 변수로 두면 편함
sudo $K3S kubectl get nodes -o wide        # 클러스터를 구성하는 서버 목록 ★
```

> 노드가 여러 대면 hostPath 기반 설정 파일(라이선스 등)은 **모든 노드에 각각** 배치해야 합니다. 파드가 어느 노드에 스케줄링될지 모르고 재기동 시 이동할 수 있으며, 노드 로컬 디스크는 서로 공유되지 않습니다.

**sudo 없이 쓰려면** (k3s 설정 파일은 기본적으로 root만 읽을 수 있음)

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config
```
> 이 파일은 클러스터 관리자 권한 자격증명입니다. 권한 600을 유지하고 외부로 공유하지 마세요.

**자주 쓰는 alias** (`~/.bashrc`에 추가)

```bash
alias k='kubectl'
alias kgp='kubectl get pods -A'
```

---

## 1. 조회

```bash
kubectl get pods -A                         # 전체 파드 (1열: 네임스페이스, 2열: 파드명) ★
kubectl get pods -n <NS>                    # 특정 네임스페이스
kubectl get pods -n <NS> -o wide            # 노드·IP까지
kubectl get pods -A | grep -v Running       # 정상이 아닌 파드만 ★
kubectl get pods -A --no-headers | awk '{split($3,a,"/"); if (a[1]!=a[2] && $4!="Completed") print}'   # READY 미충족까지 포함 ★
kubectl get events -A --sort-by=.lastTimestamp | tail -30   # 전체 네임스페이스 최근 이벤트
kubectl get pods -n <NS> -w                 # 상태 변화 실시간 감시

kubectl get nodes -o wide                   # 노드 상태
kubectl get ns                              # 네임스페이스 목록
kubectl get deploy,svc,ingress -n <NS>      # 여러 리소스 한 번에
kubectl get all -n <NS>                     # 주요 리소스 전체
kubectl get pvc -A                          # 영구 볼륨 클레임
kubectl get cm,secret -n <NS>               # ConfigMap, Secret 목록

kubectl describe pod <POD> -n <NS>          # 상세 정보 + 하단 Events ★
kubectl get events -n <NS> --sort-by=.lastTimestamp | tail -20   # 최근 이벤트
kubectl get pod <POD> -n <NS> -o yaml       # 전체 정의 (yaml)
```

### 컬럼 읽는 법

| 컬럼 | 의미 |
|---|---|
| **READY `n/n`** | **실제 사용 가능 판정 기준.** readinessProbe까지 통과 ★ |
| STATUS `Running` | 컨테이너가 떴다는 뜻일 뿐. `0/1 Running`이면 아직 서비스 미편입 |
| RESTARTS | 증가 중이면 CrashLoopBackOff 전조 |

기동 완료 판단은 **READY `n/n` + RESTARTS 안정 + 애플리케이션 로그의 기동 완료 메시지** 세 가지를 함께 봅니다. 재시작 후 정상화까지는 통상 1~5분입니다(이미지가 노드에 있으면 pull 없이 initContainer·probe 대기가 대부분).

### 파드 상태별 의미

| 상태 | 의미 | 먼저 볼 것 |
|---|---|---|
| `Running` | 정상 실행 중 | — |
| `Pending` | 스케줄링 대기 (자원 부족, PVC 미바인딩 등) | `describe`의 Events |
| `Init:0/1` | initContainer 수행 중 | `logs -c <init컨테이너>` |
| `CrashLoopBackOff` | 시작 후 계속 죽고 재시작 반복 | `logs --previous` |
| `ImagePullBackOff` / `ErrImagePull` | 이미지 못 받음 | 이미지명, 레지스트리 접근 |
| `OOMKilled` | 메모리 한도 초과로 종료 | `describe`의 Last State, limits |
| `Evicted` | 노드 자원(디스크·메모리) 부족으로 축출 | 노드 디스크 (`df -h`) |
| `Completed` | 작업 완료 후 종료 (Job 등) | — |

---

## 2. 로그

```bash
kubectl logs <POD> -n <NS>                  # 전체 로그
kubectl logs <POD> -n <NS> -f               # 실시간 ★
kubectl logs <POD> -n <NS> --tail=100       # 마지막 100줄
kubectl logs <POD> -n <NS> --since=1h       # 최근 1시간
kubectl logs <POD> -n <NS> --previous       # 직전에 죽은 컨테이너 로그 (CrashLoop 분석) ★
kubectl logs <POD> -n <NS> -c <CONTAINER>   # 컨테이너 지정
kubectl logs deploy/<DEPLOY> -n <NS> -f     # 디플로이먼트 기준
kubectl logs <POD> -n <NS> | grep -i error  # 에러만
```

---

## 3. 파드 안으로 들어가기 (exec)

```bash
kubectl exec -it <POD> -n <NS> -- /bin/bash   # 셸 접속
kubectl exec -it <POD> -n <NS> -- /bin/sh     # bash가 없을 때
kubectl exec <POD> -n <NS> -- ls -l /<경로>    # 명령만 실행
kubectl exec <POD> -n <NS> -- df -h           # 파드 내부 디스크
kubectl exec <POD> -n <NS> -- env             # 환경 변수
```

---

## 4. 파드에서 파일 추출 ★

```bash
# 1. 네임스페이스(1열)와 파드명(2열) 확인
kubectl get pod -A

# 2. 파드 안 파일 경로 확인
kubectl exec <POD> -n <NS> -- ls -l <파드내_로그경로>/

# 3. /tmp로 복사
sudo /usr/local/bin/k3s kubectl cp <NS>/<POD>:<파드내_경로>/<파일>.gz /tmp/<파일>.gz

# 4. 압축 해제 (원본 유지)
gunzip -k /tmp/<파일>.gz
```

**예시 형태**

```bash
kubectl cp <NS>/<앱>-<해시>-<해시>:<앱홈>/logs/<앱>-2026-10-13.0.log.gz /tmp/<앱>-2026-10-13.0.log.gz
```

> **참고**
> - `kubectl cp`는 컨테이너 안에 `tar`가 있어야 동작합니다. 없으면 아래 방식으로 대체합니다.
>   ```bash
>   kubectl exec <POD> -n <NS> -- cat <파드내_경로> > /tmp/<파일>
>   ```
> - 파드명은 재시작될 때마다 해시 부분이 바뀝니다. 복사 직전에 `get pod`로 다시 확인하세요.
> - 로컬로 반대 방향(호스트 → 파드)은 `kubectl cp /tmp/<파일> <NS>/<POD>:<경로>`.

---

## 5. 파드 UID로 파드 이름 찾기

디스크 분석 중 `/var/lib/kubelet/pods/<POD_UID>/` 경로가 크게 나왔을 때, 어떤 파드인지 찾는 방법입니다.

**방법 1 — kubectl로 조회 (권장)**

```bash
kubectl get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,UID:.metadata.uid | grep <POD_UID>
```

**방법 2 — 파드 디렉터리의 etc-hosts 확인**

```bash
sudo cat /var/lib/kubelet/pods/<POD_UID>/etc-hosts
```
→ 파일 하단에 파드 IP와 파드 호스트명(= 파드명)이 적혀 있습니다.

**UID 디렉터리별 용량 확인**

```bash
sudo du -xh --max-depth=1 /var/lib/kubelet/pods 2>/dev/null | sort -rh | head
```

---

## 6. 자원 사용량

```bash
kubectl top nodes                           # 노드별 CPU/메모리 (k3s는 metrics-server 기본 포함)
kubectl top pods -A --sort-by=memory | head # 메모리 많이 쓰는 파드
kubectl top pods -n <NS> --containers       # 컨테이너 단위
kubectl describe node <NODE> | grep -A 10 "Allocated resources"   # 노드 할당량
```

---

## 7. 재시작·스케일

```bash
kubectl rollout restart deploy/<DEPLOY> -n <NS>   # 무중단 재시작 (권장) ★
kubectl rollout status deploy/<DEPLOY> -n <NS>    # 재시작 진행 상황
kubectl rollout history deploy/<DEPLOY> -n <NS>   # 배포 이력
kubectl rollout undo deploy/<DEPLOY> -n <NS>      # 직전 버전으로 롤백

kubectl scale deploy/<DEPLOY> -n <NS> --replicas=0   # 중지
kubectl scale deploy/<DEPLOY> -n <NS> --replicas=1   # 재개
kubectl get pod <POD> -n <NS> -o jsonpath='{.metadata.ownerReferences}'   # 관리 컨트롤러 확인 (없으면 delete 후 안 뜸)

kubectl delete pod <POD> -n <NS>                  # 파드 삭제 (디플로이먼트가 새로 생성)
```

> - 디플로이먼트가 관리하는 파드는 `delete pod`해도 자동으로 다시 생깁니다. 완전히 멈추려면 `scale --replicas=0`.
> - `rollout restart`는 새 파드가 뜬 뒤 이전 파드를 내리므로 `delete pod`보다 안전합니다.
> - 상태를 가진 클러스터형 워크로드(헤드-워커 구조 등)는 헤드 파드를 지우면 **클러스터 전체가 재초기화**되어 진행 중 작업이 유실될 수 있습니다. 워커부터 순차 재시작하고, 재시작 전후로 영향 범위와 회수량을 기록하세요.

---

## 8. k3s·컨테이너 런타임 (containerd)

k3s는 Docker 대신 containerd를 쓰므로 `docker` 대신 `crictl`을 사용합니다.

```bash
sudo k3s crictl ps                          # 실행 중인 컨테이너
sudo k3s crictl ps -a                       # 종료된 것 포함
sudo k3s crictl images                      # 이미지 목록
sudo k3s crictl logs <컨테이너ID>             # 컨테이너 로그 (kubectl 안 될 때)
sudo k3s crictl inspect <컨테이너ID>          # 상세 정보
sudo k3s crictl images --digests             # 이미지 목록·크기·다이제스트
sudo k3s crictl imagefsinfo                  # 이미지 파일시스템 총점유
sudo k3s crictl stats -a                     # 컨테이너별 CPU/MEM/DISK/INODES ★
```

- `crictl ps`의 CREATED 컬럼으로 컨테이너 재시작 여부를 확인할 수 있습니다.
- `stats`의 **MEM은 RAM, DISK는 쓰기 레이어 크기**입니다. 서로 다른 축이므로 혼동 주의.
- 표는 단위(kB/MB/GB)가 섞여 상위를 놓치기 쉬우니 JSON으로 정렬해서 보세요 (`jq` 필요).

```bash
# 쓰기 레이어 큰 순 ★
sudo k3s crictl stats -a -o json | jq -r '
  .stats[] | [(.writableLayer.usedBytes.value // 0 | tonumber),
              (.attributes.metadata.name // "?"), .attributes.id[0:13]] | @tsv' \
  | sort -rn | head -10 | numfmt --field=1 --to=iec
```

### k3s 서비스

```bash
systemctl status k3s                        # 서버 노드
systemctl status k3s-agent                  # 에이전트(워커) 노드
sudo journalctl -u k3s -f                   # k3s 로그 실시간
sudo journalctl -u k3s --since "1 hour ago"
sudo systemctl restart k3s                  # 재시작 (클러스터 전체에 영향, 신중히)
```

### 디스크 관련 경로

| 경로 | 내용 |
|---|---|
| `/var/lib/rancher/k3s/agent/containerd` | 이미지·컨테이너 레이어 (가장 큰 경우가 많음) |
| `/var/lib/rancher/k3s/storage` | local-path 기본 PV 데이터 |
| `/var/lib/rancher/k3s/server/db` | 클러스터 DB (sqlite/etcd) |
| `/var/lib/kubelet/pods` | 파드별 볼륨 (emptyDir 등) |
| `/var/log/pods`, `/var/log/containers` | 컨테이너 로그 |

```bash
sudo du -xh --max-depth=3 /var/lib/rancher/k3s 2>/dev/null | sort -rh | head -15
sudo du -xh --max-depth=1 /var/log/pods 2>/dev/null | sort -rh | head
```

### containerd 저장소 구조

```
<K3S_ROOT>/agent/containerd/
├── io.containerd.content.v1.content        # pull 당시의 압축 블롭(이미지 원본)
├── io.containerd.snapshotter.v1.overlayfs/
│   └── snapshots/<번호>/fs                 # 이미지 레이어 + 컨테이너 쓰기 레이어
└── io.containerd.metadata.v1.bolt
```

```bash
sudo du -xm --max-depth=1 <K3S_ROOT>/agent/containerd 2>/dev/null | sort -rn | head
sudo du -xm --max-depth=1 <K3S_ROOT>/agent/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots \
  2>/dev/null | sort -rn | head -15                                     # ★
```

### 증가 원인 분기

| 관찰 | 해석 | 조치 |
|---|---|---|
| `content` 증가 | 새 이미지 pull | 배포 이력 확인, `rmi --prune` |
| `content` 불변 + `overlayfs`만 증가 | **실행 중 컨테이너의 쓰기 레이어** | prune으로 회수 불가 → 앱 설정 교정 |
| `storage/`(local-path PVC) 증가 | 애플리케이션 데이터 | 해당 워크로드의 보존정책 |
| `/var/log/pods/` 증가 | 파드 stdout 로그 | kubelet 로그 로테이션 설정 |
| `/var/lib/kubelet/pods/<UID>/volumes` 증가 | emptyDir 등 볼륨 데이터 | 5장으로 UID→파드 변환 후 앱 확인 |

### 스냅샷 번호 → 컨테이너 이름 대조

`du`는 번호만, `crictl stats`는 이름만 알려주므로 **크기가 맞물리는 행**을 찾아 신원을 확인합니다. (du는 MiB, crictl은 GB 표기 → `MiB × 1.048576 = MB`, 1000으로 나누면 GB)

| 스냅샷 ID | du(MiB) | 환산 | crictl DISK | 컨테이너 |
|---|---|---|---|---|
| `<ID>` | 15,690 | 16.45GB | 16.45GB | `<CONTAINER>` |

- 서로 다른 두 측정(파일시스템 / 런타임 장부)이 일치하면 귀속이 확정됩니다.
- 한 번의 대조는 "현재 보유량"만 증명합니다. **증가 주체**를 증명하려면 시간 간격을 둔 두 측정에서 "어느 스냅샷만 늘고 나머지는 불변"인지를 봐야 합니다.
- 컨테이너가 재시작되면 스냅샷 ID가 바뀌고 크기가 0부터 다시 시작합니다. 장기 추적은 ID가 아닌 **이름 기준**(`stats -o json`)으로 하세요.

### 이미지 정리

```bash
sudo k3s crictl imagefsinfo                 # 정리 전 점유량
sudo k3s crictl images                      # 정리 전 목록 확인
sudo k3s crictl rmi --prune                 # 사용하지 않는 이미지 삭제 ★
sudo k3s crictl imagefsinfo                 # 정리 후 점유량 비교
```

> - `--prune`은 **현재 실행 중인 컨테이너가 쓰지 않는 이미지**를 지웁니다. 스케일 0으로 내려둔 서비스의 이미지도 지워질 수 있고, 다시 올릴 때 레지스트리에서 받아야 합니다(폐쇄망이면 특히 주의).
> - `/var/lib/rancher` 아래 파일을 `rm`으로 직접 지우지 마세요. 런타임 상태가 깨질 수 있습니다.
> - 노드 디스크가 차면 kubelet이 파드를 `Evicted` 시키기 시작합니다. `kubectl get pods -A | grep Evicted`로 확인하세요.

### 자동 정리(GC)의 관할 범위

| 항목 | 자동 정리 주체 |
|---|---|
| 미사용 이미지 | kubelet 이미지 GC (기본: 사용률 85% 초과 시 발동, 80%까지 회수) |
| 죽은 컨테이너 | kubelet 컨테이너 GC |
| 파드 stdout 로그 | kubelet 로그 로테이션 (`containerLogMaxSize` 등) |
| **실행 중 컨테이너의 쓰기 레이어** | **없음** |
| PVC·hostPath 데이터 | 없음 (앱의 보존정책 몫) |
| 한계 도달 시 | eviction = 파드 축출 (정리가 아니라 장애) |

디스크가 갑자기 수십 GB 줄었다면 이미지 GC 발동을 의심합니다.

```bash
journalctl -u k3s --since '<YYYY-MM-DD>' | grep -iE 'over the high threshold|trying to free|imageGC'
```

- 쓰기 레이어는 GC 대상이 아니므로, 커지는 워크로드는 **로그·임시데이터 경로를 볼륨으로 분리하고 로테이션을 설정**해야 근본 해결됩니다. 재시작은 일시 회수일 뿐입니다.
- 벤더 배포 차트 영역이라면 수치를 근거로 공급사에 요청하는 것이 정석입니다 (직접 수정 시 다음 배포에서 원복되고 지원 범위 문제도 생김).

---

## 9. k9s (터미널 UI)

```bash
k9s                                         # 실행 (~/.kube/config 사용)
k9s -n <NS>                                 # 네임스페이스 지정
k9s --readonly                              # 삭제·편집 비활성 — 운영 모니터링 시 권장 ★
sudo $(which k9s) --kubeconfig /etc/rancher/k3s/k3s.yaml   # kubeconfig를 복사하지 않은 경우
```

| 키 | 동작 |
|---|---|
| `:pod` `:deploy` `:sts` `:svc` `:ns` `:node` `:events` | 리소스 뷰 전환 (축약 가능) |
| `Ctrl+A` | 사용 가능한 전체 리소스 목록 |
| `0` / `1~9` | 전체 네임스페이스 / 즐겨찾기 전환 |
| `/<문자열>` | 필터, `Esc` 해제 |
| `Shift+C` / `Shift+M` | CPU / MEM 정렬 ★ |
| `d` / `y` / `e` | describe / YAML / 편집 |
| `l` / `s` / `a` | 로그 / 셸 접속 / attach |
| `Ctrl+D` / `Ctrl+K` | 삭제 / 강제 종료 (주의) |
| `r` | rollout restart (deploy·sts 뷰에서만) |
| `Shift+F` | 포트포워드 |
| `:pulse` / `:xray deploy` / `Ctrl+Z` | 상태 대시보드 / 소유관계 트리 / 문제 리소스만 |
| `?` | 현재 뷰의 단축키 전체 |
| `q` / `Esc` | 뒤로 / 종료 |

- 셸(`s`)에서 나올 때는 `exit` 또는 `Ctrl+D`. **`Ctrl+C`는 세션이 어정쩡하게 남습니다.**
- `d`(describe)와 `Ctrl+D`(삭제)가 인접하므로 파드 뷰에서 오조작 주의.

---

## 10. 실수 방지 체크리스트

- 명령 실행 전 **네임스페이스(`-n`) 확인**. 빠뜨리면 `default`에서 실행됨
- `kubectl delete`는 되돌릴 수 없음 → `get`으로 대상 먼저 확인
- `delete ns <NS>`는 그 안의 모든 리소스를 삭제함
- 재시작은 `delete pod`보다 `rollout restart` 우선
- 파드 상태는 STATUS가 아니라 **READY `n/n`**으로 판단
- 운영 모니터링 시 k9s는 `--readonly`로 실행
- `/var/lib/rancher`, `/var/lib/kubelet` 아래는 직접 삭제 금지 → `crictl`, `kubectl`로 정리
- `k3s.yaml`(kubeconfig)은 관리자 자격증명 → 권한 600, 외부 공유 금지
- 문서 공유 시 네임스페이스, 파드명, 앱 경로, 노드 IP는 플레이스홀더로 유지
