(function () {
	const HIDE_CLASS = 'owui-hide-model-for-user';

	function injectStyle() {
		if (document.getElementById('owui-hide-model-style')) return;
		const style = document.createElement('style');
		style.id = 'owui-hide-model-style';
		style.textContent = `
			html.${HIDE_CLASS} #response-message-model-name,
			html.${HIDE_CLASS} [id^="model-selector-"],
			html.${HIDE_CLASS} nav .max-w-full.mr-1,
			html.${HIDE_CLASS} .font-primary .flex.flex-row .shrink-0 {
				display: none !important;
			}
		`;
		document.head.appendChild(style);
	}

	async function fetchUser() {
		const token = localStorage.getItem('token');
		if (!token) return null;
		const res = await fetch('/api/v1/auths/', {
			headers: { Authorization: `Bearer ${token}` },
			credentials: 'include'
		});
		if (!res.ok) return null;
		return res.json();
	}

	function fixWelcomeTitle(user) {
		const el = document.querySelector('.font-primary .text-3xl .line-clamp-1');
		if (!el) return;
		el.textContent = `สวัสดี, ${user?.name ?? ''}`.trim();
	}

	async function sync() {
		injectStyle();
		const user = await fetchUser();
		if (!user) {
			document.documentElement.classList.remove(HIDE_CLASS);
			return;
		}
		if (user.role === 'admin') {
			document.documentElement.classList.remove(HIDE_CLASS);
			return;
		}
		document.documentElement.classList.add(HIDE_CLASS);
		fixWelcomeTitle(user);
	}

	sync();
	window.addEventListener('storage', sync);
	setInterval(sync, 5000);
	new MutationObserver(() => sync()).observe(document.documentElement, {
		childList: true,
		subtree: true
	});
})();
