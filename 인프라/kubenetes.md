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

### k3s에서 kubectl 실행

```bash
sudo k3s kubectl get pods -A                     # k3s 내장 kubectl
sudo /usr/local/bin/k3s kubectl get pods -A      # PATH에 없을 때 전체 경로
kubectl get pods -A                              # kubectl이 설정된 경우
```

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

### 파드 상태별 의미

| 상태 | 의미 | 먼저 볼 것 |
|---|---|---|
| `Running` | 정상 실행 중 | — |
| `Pending` | 스케줄링 대기 (자원 부족, PVC 미바인딩 등) | `describe`의 Events |
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

kubectl delete pod <POD> -n <NS>                  # 파드 삭제 (디플로이먼트가 새로 생성)
```

> - 디플로이먼트가 관리하는 파드는 `delete pod`해도 자동으로 다시 생깁니다. 완전히 멈추려면 `scale --replicas=0`.
> - `rollout restart`는 새 파드가 뜬 뒤 이전 파드를 내리므로 `delete pod`보다 안전합니다.

---

## 8. k3s·컨테이너 런타임 (containerd)

k3s는 Docker 대신 containerd를 쓰므로 `docker` 대신 `crictl`을 사용합니다.

```bash
sudo k3s crictl ps                          # 실행 중인 컨테이너
sudo k3s crictl ps -a                       # 종료된 것 포함
sudo k3s crictl images                      # 이미지 목록
sudo k3s crictl logs <컨테이너ID>             # 컨테이너 로그 (kubectl 안 될 때)
sudo k3s crictl inspect <컨테이너ID>          # 상세 정보
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

### 이미지 정리

```bash
sudo k3s crictl images                      # 정리 전 목록 확인
sudo k3s crictl rmi --prune                 # 사용하지 않는 이미지 삭제 ★
```

> - `--prune`은 **현재 실행 중인 컨테이너가 쓰지 않는 이미지**를 지웁니다. 스케일 0으로 내려둔 서비스의 이미지도 지워질 수 있고, 다시 올릴 때 레지스트리에서 받아야 합니다(폐쇄망이면 특히 주의).
> - `/var/lib/rancher` 아래 파일을 `rm`으로 직접 지우지 마세요. 런타임 상태가 깨질 수 있습니다.
> - 노드 디스크가 차면 kubelet이 파드를 `Evicted` 시키기 시작합니다. `kubectl get pods -A | grep Evicted`로 확인하세요.

---

## 9. k9s (터미널 UI)

```bash
k9s                                         # 실행
k9s -n <NS>                                 # 네임스페이스 지정
```

| 키 | 동작 |
|---|---|
| `:pod` / `:deploy` / `:svc` | 리소스 종류 전환 |
| `/` | 필터 |
| `l` | 로그 |
| `s` | 셸 접속 |
| `d` | describe |
| `Ctrl+d` | 삭제 (주의) |
| `0` | 전체 네임스페이스 |
| `q` / `Esc` | 뒤로 / 종료 |

---

## 10. 실수 방지 체크리스트

- 명령 실행 전 **네임스페이스(`-n`) 확인**. 빠뜨리면 `default`에서 실행됨
- `kubectl delete`는 되돌릴 수 없음 → `get`으로 대상 먼저 확인
- `delete ns <NS>`는 그 안의 모든 리소스를 삭제함
- 재시작은 `delete pod`보다 `rollout restart` 우선
- `/var/lib/rancher`, `/var/lib/kubelet` 아래는 직접 삭제 금지 → `crictl`, `kubectl`로 정리
- `k3s.yaml`(kubeconfig)은 관리자 자격증명 → 권한 600, 외부 공유 금지
- 문서 공유 시 네임스페이스, 파드명, 앱 경로, 노드 IP는 플레이스홀더로 유지
