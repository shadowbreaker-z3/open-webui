(function () {
	if (!/^\/auth\/?$/.test(location.pathname)) return;

	const STYLE_ID = 'ldap-only-style';
	const OVERLAY_ID = 'ldap-only-overlay';

	async function getConfig() {
		const res = await fetch('/api/config', { credentials: 'include' });
		if (!res.ok) return null;
		return res.json();
	}

	function ldapOnly(cfg) {
		return cfg?.features?.enable_ldap && !cfg?.features?.enable_login_form;
	}

	function isDark() {
		return document.documentElement.classList.contains('dark');
	}

	function injectStyles() {
		if (document.getElementById(STYLE_ID)) return;
		const style = document.createElement('style');
		style.id = STYLE_ID;
		style.textContent = `
			#${OVERLAY_ID} {
				position: fixed;
				inset: 0;
				z-index: 99999;
				display: flex;
				align-items: center;
				justify-content: center;
				padding: 1.5rem;
				background: #fff;
				color: #111;
				font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
			}
			html.dark #${OVERLAY_ID} {
				background: #000;
				color: #f3f4f6;
			}
			#${OVERLAY_ID} .ldap-card {
				width: 100%;
				max-width: 28rem;
				text-align: center;
			}
			#${OVERLAY_ID} .ldap-title {
				font-size: 1.5rem;
				font-weight: 500;
				margin-bottom: 0.25rem;
			}
			#${OVERLAY_ID} .ldap-subtitle {
				font-size: 0.875rem;
				color: #6b7280;
				margin-bottom: 1.5rem;
			}
			html.dark #${OVERLAY_ID} .ldap-subtitle {
				color: #9ca3af;
			}
			#${OVERLAY_ID} label {
				display: block;
				text-align: left;
				font-size: 0.875rem;
				font-weight: 500;
				margin-bottom: 0.25rem;
			}
			#${OVERLAY_ID} .ldap-field {
				margin-bottom: 0.75rem;
			}
			#${OVERLAY_ID} input {
				width: 100%;
				box-sizing: border-box;
				padding: 0.625rem 0;
				font-size: 0.875rem;
				border: 0;
				border-bottom: 1px solid #d1d5db;
				background: transparent;
				color: inherit;
				outline: none;
			}
			html.dark #${OVERLAY_ID} input {
				border-bottom-color: #374151;
			}
			#${OVERLAY_ID} input::placeholder {
				color: #9ca3af;
			}
			#${OVERLAY_ID} button[type="submit"] {
				margin-top: 1.25rem;
				width: 100%;
				border: 0;
				border-radius: 9999px;
				padding: 0.625rem 1rem;
				font-size: 0.875rem;
				font-weight: 500;
				cursor: pointer;
				background: rgba(55, 65, 81, 0.08);
				color: inherit;
			}
			html.dark #${OVERLAY_ID} button[type="submit"] {
				background: rgba(243, 244, 246, 0.08);
			}
			#${OVERLAY_ID} button[type="submit"]:hover {
				background: rgba(55, 65, 81, 0.14);
			}
			html.dark #${OVERLAY_ID} button[type="submit"]:hover {
				background: rgba(243, 244, 246, 0.14);
			}
			#${OVERLAY_ID} .ldap-error {
				margin-top: 0.75rem;
				font-size: 0.875rem;
				color: #dc2626;
			}
		`;
		document.head.appendChild(style);
	}

	function buildOverlay(cfg) {
		const existing = document.getElementById(OVERLAY_ID);
		if (existing) return existing;

		injectStyles();

		const overlay = document.createElement('div');
		overlay.id = OVERLAY_ID;
		overlay.innerHTML = `
			<div class="ldap-card">
				<div class="ldap-title">เข้าสู่ระบบด้วย Active Directory</div>
				<div class="ldap-subtitle">${cfg?.name || 'Open WebUI'} · ${cfg?.features?.enable_ldap ? 'ombudsman.go.th' : ''}</div>
				<form id="ldap-only-form" autocomplete="on">
					<div class="ldap-field">
						<label for="ldap-only-username">ชื่อผู้ใช้</label>
						<input
							id="ldap-only-username"
							name="username"
							type="text"
							autocomplete="username"
							placeholder="กรอกชื่อผู้ใช้ (sAMAccountName)"
							required
						/>
					</div>
					<div class="ldap-field">
						<label for="ldap-only-password">รหัสผ่าน</label>
						<input
							id="ldap-only-password"
							name="password"
							type="password"
							autocomplete="current-password"
							placeholder="กรอกรหัสผ่าน AD"
							required
						/>
					</div>
					<button type="submit">เข้าสู่ระบบ</button>
					<div class="ldap-error" id="ldap-only-error" hidden></div>
				</form>
			</div>
		`;

		document.body.appendChild(overlay);

		const form = overlay.querySelector('#ldap-only-form');
		const errorEl = overlay.querySelector('#ldap-only-error');

		form.addEventListener('submit', async (e) => {
			e.preventDefault();
			errorEl.hidden = true;
			errorEl.textContent = '';

			const user = overlay.querySelector('#ldap-only-username').value.trim();
			const password = overlay.querySelector('#ldap-only-password').value;

			if (!user || !password) return;

			const submitBtn = form.querySelector('button[type="submit"]');
			submitBtn.disabled = true;
			submitBtn.textContent = 'กำลังเข้าสู่ระบบ...';

			try {
				const res = await fetch('/api/v1/auths/ldap', {
					method: 'POST',
					headers: { 'Content-Type': 'application/json' },
					credentials: 'include',
					body: JSON.stringify({ user, password })
				});

				if (!res.ok) {
					let message = 'เข้าสู่ระบบไม่สำเร็จ';
					try {
						const err = await res.json();
						message = err.detail || message;
					} catch {
						// ignore
					}
					errorEl.textContent = message;
					errorEl.hidden = false;
					return;
				}

				const sessionUser = await res.json();
				if (sessionUser?.token) {
					localStorage.setItem('token', sessionUser.token);
				}

				const redirect = localStorage.getItem('redirectPath') || '/';
				localStorage.removeItem('redirectPath');
				location.href = redirect;
			} finally {
				submitBtn.disabled = false;
				submitBtn.textContent = 'เข้าสู่ระบบ';
			}
		});

		return overlay;
	}

	function hideDefaultAuthUi() {
		const authPage = document.getElementById('auth-page');
		if (authPage) authPage.style.visibility = 'hidden';
	}

	async function ensureLdapOnlyUi() {
		const cfg = await getConfig();
		if (!ldapOnly(cfg)) {
			const overlay = document.getElementById(OVERLAY_ID);
			if (overlay) overlay.remove();
			const authPage = document.getElementById('auth-page');
			if (authPage) authPage.style.visibility = '';
			return;
		}

		hideDefaultAuthUi();
		buildOverlay(cfg);
	}

	ensureLdapOnlyUi();
	new MutationObserver(() => ensureLdapOnlyUi()).observe(document.documentElement, {
		childList: true,
		subtree: true
	});
})();
