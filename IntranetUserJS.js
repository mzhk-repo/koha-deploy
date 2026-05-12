/**
 * Koha-to-DSpace Integration Script (v6.1 Async)
 * Документація: Скрипт додає кнопки архівації/оновлення в інтерфейс Koha.
 */

$(document).ready(function() {
    // --- 1. КОНФІГУРАЦІЯ ---
    const KDV_CONFIG = {
        API_URL: "https://repo.pinokew.buzz/kdv/api",
        REPO_DOMAIN: "repo.pinokew.buzz",
        POLLING_INTERVAL: 2000,
        MAX_POLLING_ATTEMPTS: 30, // Захист від нескінченного циклу (1 хвилина)
        I18N: {
            updateBtn: "Оновити метадані DSpace",
            archiveBtn: "Архівувати в DSpace",
            confirmArchive: "Архівувати книгу в DSpace? (Фоновий процес)",
            confirmUpdate: "Оновити метадані (Назву, Автора) в DSpace?",
            success: "✅ Дію завершено успішно!",
            error: "❌ Помилка: ",
            authNeeded: "Потрібна авторизація. Відкрийте вікно, що з'явилося, і повторіть дію."
        }
    };

    const KDV_TOKEN = (window.KDV_TOKEN || "").trim();

    /**
     * Визначає, чи вже є запис у репозиторії
     */
    function detectArchivedRecord() {
        let foundByLink = false;
        const repoDomainLower = KDV_CONFIG.REPO_DOMAIN.toLowerCase();

        $("a[href]").each(function() {
            const href = ($(this).attr("href") || "").trim().toLowerCase();
            if (!href || href.includes("/kdv/api")) return;

            if (
                (repoDomainLower && href.includes(repoDomainLower)) ||
                href.includes("/handle/") ||
                href.includes("/items/")
            ) {
                foundByLink = true;
                return false;
            }
        });

        if (foundByLink) return true;

        const detailsText = $("#catalogue_detail_biblio, .bibliodetails, #details, .results_summary")
            .text()
            .toLowerCase();

        return detailsText && detailsText.includes("856") && (
            detailsText.includes("/handle/") || 
            detailsText.includes("/items/") || 
            (repoDomainLower && detailsText.includes(repoDomainLower))
        );
    }

    function buildHeaders() {
        return KDV_TOKEN ? { "X-KDV-TOKEN": KDV_TOKEN } : {};
    }

    // Точка входу: перевірка сторінки деталей
    if (window.location.href.includes("catalogue/detail.pl")) {
        const urlParams = new URLSearchParams(window.location.search);
        const biblionumber = urlParams.get('biblionumber');
        if (biblionumber) renderIntegrationTools(biblionumber);
    }

    function renderIntegrationTools(biblionumber) {
        const isArchived = detectArchivedRecord();
        const toolbar = $("#toolbar");
        if (toolbar.length === 0) return;

        const btnConfig = isArchived 
            ? { id: "kdv-update-btn", icon: "fa-refresh", text: KDV_CONFIG.I18N.updateBtn, method: "PUT" }
            : { id: "kdv-integrate-btn", icon: "fa-cloud-upload", text: KDV_CONFIG.I18N.archiveBtn, method: "POST" };

        const btnHtml = `
            <div class="btn-group">
                <button id="${btnConfig.id}" class="btn btn-default btn-sm" style="${isArchived ? 'color: #007bff; font-weight: bold;' : ''}">
                    <i class="fa ${btnConfig.icon}"></i> ${btnConfig.text}
                </button>
            </div>
        `;
        toolbar.append(btnHtml);

        // Обробник натискання
        $(`#${btnConfig.id}`).click(function(e) {
            e.preventDefault();
            const confirmMsg = isArchived ? KDV_CONFIG.I18N.confirmUpdate : KDV_CONFIG.I18N.confirmArchive;
            if (!confirm(confirmMsg)) return;

            const btn = $(this);
            const originalHtml = btn.html();
            btn.prop("disabled", true).html('<i class="fa fa-spinner fa-spin"></i> Обробка...');

            ensureAccessSession(() => {
                $.ajax({
                    url: `${KDV_CONFIG.API_URL}/integrate/${biblionumber}`,
                    type: btnConfig.method,
                    xhrFields: { withCredentials: true },
                    headers: buildHeaders(),
                    success: (res) => {
                        if (btnConfig.method === "POST" && res.task_id) {
                            startPolling(res.task_id, btn, originalHtml);
                        } else {
                            alert(KDV_CONFIG.I18N.success);
                            location.reload();
                        }
                    },
                    error: (xhr) => {
                        const msg = xhr.responseJSON?.message || xhr.statusText;
                        showError(btn, msg, originalHtml);
                    }
                });
            }, () => {
                btn.prop("disabled", false).html(originalHtml);
            });
        });
    }

    function ensureAccessSession(onReady, onFail) {
        $.ajax({
            url: `${KDV_CONFIG.API_URL}/health`,
            type: "GET",
            xhrFields: { withCredentials: true },
            headers: buildHeaders(),
            success: onReady,
            error: () => {
                alert(KDV_CONFIG.I18N.authNeeded);
                window.open(`${KDV_CONFIG.API_URL}/health`, "_blank", "noopener,noreferrer");
                if (onFail) onFail();
            }
        });
    }

    function startPolling(taskId, btn, originalHtml) {
        let attempts = 0;
        const pollTimer = setInterval(() => {
            attempts++;
            if (attempts > KDV_CONFIG.MAX_POLLING_ATTEMPTS) {
                clearInterval(pollTimer);
                showError(btn, "Перевищено час очікування", originalHtml);
                return;
            }

            $.ajax({
                url: `${KDV_CONFIG.API_URL}/status/${taskId}`,
                type: "GET",
                xhrFields: { withCredentials: true },
                headers: buildHeaders(),
                success: (data) => {
                    if (data.status === 'success') {
                        clearInterval(pollTimer);
                        btn.addClass("btn-success").html('<i class="fa fa-check"></i>');
                        alert(`${KDV_CONFIG.I18N.success}\nHandle: ${data.result?.handle}`);
                        location.reload();
                    } else if (data.status === 'error') {
                        clearInterval(pollTimer);
                        showError(btn, data.error, originalHtml);
                    }
                },
                error: (xhr) => {
                    if (xhr.status === 404 || xhr.status === 401) {
                        clearInterval(pollTimer);
                        showError(btn, `Помилка статусу: ${xhr.status}`, originalHtml);
                    }
                }
            });
        }, KDV_CONFIG.POLLING_INTERVAL);
    }

    function showError(btn, msg, originalHtml) {
        alert(KDV_CONFIG.I18N.error + msg);
        btn.prop("disabled", false).addClass("btn-danger").html(originalHtml);
        setTimeout(() => btn.removeClass("btn-danger"), 3000);
    }
});