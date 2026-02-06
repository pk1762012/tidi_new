package tidistock

import grails.core.GrailsApplication
import grails.gorm.transactions.Transactional
import groovy.json.JsonSlurper
import groovy.json.JsonOutput
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.scheduling.annotation.Scheduled
import okhttp3.*

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit

@Transactional
class CallJobService {

    private static final OkHttpClient HTTP_CLIENT = new OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()

    @Autowired
    GrailsApplication grailsApplication

    def fireBaseService

    private LocalDate lastCheckedDate = null
    private boolean isMarketOpenToday = false


    static lazyInit = false

    @Scheduled(cron = "0 59 23 * * ?", zone = "Asia/Kolkata")
    void expireSubscriptions() {
        def today = LocalDate.now()
        def startOfDay = today.atStartOfDay(ZoneId.of("Asia/Kolkata")).toInstant()
        def endOfDay = today.plusDays(1).atStartOfDay(ZoneId.of("Asia/Kolkata")).toInstant()

        List<Subscription> subscriptions = Subscription.findAllByExpirationDateBetween(
                Date.from(startOfDay),
                Date.from(endOfDay)
        )

        if (!subscriptions.isEmpty()) {
            // Pre-fetch Subscription->User->fcmToken mapping in a single query
            Map<Long, String> tokenMap = [:]
            try {
                def tokenRows = User.executeQuery("""
                    SELECT s.id, u.fcmToken FROM User u
                    JOIN u.wallet w JOIN w.subscription s
                    WHERE s IN :subscriptions AND u.fcmToken IS NOT NULL
                """, [subscriptions: subscriptions])
                tokenMap = tokenRows.collectEntries { [(it[0]): it[1]] }
            } catch (Exception e) {
                log.error("Failed to pre-fetch FCM tokens for expiring subscriptions", e)
            }

            subscriptions.forEach {
                it.isSubscribed = false
                it.subscriptionType = null
                it.expirationDate = null
                it.save()

                String fcmToken = tokenMap[it.id]

                if (fcmToken) {
                    fireBaseService.sendToToken(
                            fcmToken,
                            "TIDI Membership Expired – Renew for ₹249",
                            "Your membership has expired. Renew now to continue enjoying premium TIDI features."
                    );
                }

            }
            Subscription.withSession { it.flush() }
        }

    }

    @Scheduled(cron = "0 0 10 * * ?", zone = "Asia/Kolkata")
    void notifyExpiringSubscriptions() {
        LocalDate today = LocalDate.now(ZoneId.of("Asia/Kolkata"))

        // Notify users whose subscription is expiring in 5 -> 0 days
        (0..5).each { daysLeft ->
            LocalDate targetDate = today.plusDays(daysLeft)
            Date startOfDay = Date.from(targetDate.atStartOfDay(ZoneId.systemDefault()).toInstant())
            Date endOfDay = Date.from(targetDate.plusDays(1).atStartOfDay(ZoneId.systemDefault()).minusNanos(1).toInstant())

            List<Subscription> expiring = Subscription.findAllByExpirationDateBetweenAndIsSubscribed(
                    startOfDay, endOfDay, true
            )

            if (!expiring.isEmpty()) {
                Map<Long, String> tokenMap = [:]
                try {
                    def tokenRows = User.executeQuery("""
                        SELECT s.id, u.fcmToken FROM User u
                        JOIN u.wallet w JOIN w.subscription s
                        WHERE s IN :subscriptions AND u.fcmToken IS NOT NULL
                    """, [subscriptions: expiring])
                    tokenMap = tokenRows.collectEntries { [(it[0]): it[1]] }
                } catch (Exception e) {
                    log.error("Failed to pre-fetch FCM tokens for expiring subscriptions", e)
                }

                expiring.each { sub ->
                    String fcmToken = tokenMap[sub.id]

                    if (fcmToken) {
                        fireBaseService.sendToToken(
                                fcmToken,
                                "TIDI Membership Expiring Soon – ₹249",
                                "Only ${daysLeft} day(s) left! Renew now and keep uninterrupted access to all premium TIDI features."
                        )
                    }
                }
            }
        }

        List<Subscription> expired = Subscription.findAllByIsSubscribed(false)
        if (!expired.isEmpty()) {
            Map<Long, String> expiredTokenMap = [:]
            try {
                def tokenRows = User.executeQuery("""
                    SELECT s.id, u.fcmToken FROM User u
                    JOIN u.wallet w JOIN w.subscription s
                    WHERE s IN :subscriptions AND u.fcmToken IS NOT NULL
                """, [subscriptions: expired])
                expiredTokenMap = tokenRows.collectEntries { [(it[0]): it[1]] }
            } catch (Exception e) {
                log.error("Failed to pre-fetch FCM tokens for expired subscriptions", e)
            }

            expired.each { sub ->
                String fcmToken = expiredTokenMap[sub.id]

                if (fcmToken) {
                    fireBaseService.sendToToken(
                            fcmToken,
                            "Get TIDI Membership – Just ₹249",
                            "Unlock all premium TIDI features instantly. Subscribe now for only ₹249."
                    );
                }
            }
        }
    }

    @Scheduled(cron = "0 0 8 * * ?", zone = "Asia/Kolkata")
    void createPreMarketData() {
        ZonedDateTime now = ZonedDateTime.now(ZoneId.of("Asia/Kolkata"))
        if (now.getDayOfWeek() != DayOfWeek.SATURDAY && now.getDayOfWeek() != DayOfWeek.SUNDAY && !isMarketHoliday(LocalDate.now())) {
            preMarketApiTrigger()
        }
        nifty50StockCacheTrigger()
    }

    @Scheduled(cron = "0 30 19 * * ?", zone = "Asia/Kolkata")
    void fetchNseData() {
        ZonedDateTime now = ZonedDateTime.now(ZoneId.of("Asia/Kolkata"))
        if (now.getDayOfWeek() != DayOfWeek.SATURDAY && now.getDayOfWeek() != DayOfWeek.SUNDAY && !isMarketHoliday(LocalDate.now())) {
            getNseDataApiTrigger()
        }
    }

    @Scheduled(cron = "0 0 9 * * ?", zone = "Asia/Kolkata")
    void refreshMarketWS() {
        ZonedDateTime now = ZonedDateTime.now(ZoneId.of("Asia/Kolkata"))
        if (now.getDayOfWeek() != DayOfWeek.SATURDAY && now.getDayOfWeek() != DayOfWeek.SUNDAY && !isMarketHoliday(LocalDate.now())) {
            refreshMarketCreds()
        }
    }

    void refreshMarketCreds() {
        String apiUrl = grailsApplication.config.market.api.url
        String apiPassword = grailsApplication.config.market.api.password

        Request request = new Request.Builder()
                .url(apiUrl+"admin/nifty_option/refresh")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = HTTP_CLIENT.newCall(request).execute()) {
            if (response.successful) {
                log.info("Market WS creds refreshed")

            } else {
                log.error("Error while refreshing Market WS creds. Response code: ${response.code()}")
            }
        } catch (Exception e) {
            log.error("Exception while refreshing Market WS creds", e)
        }
    }


    @Scheduled(cron = "0 0/1 9-16 ? * MON-FRI", zone = "Asia/Kolkata")
    void cacheMarketData() {
        ZonedDateTime now = ZonedDateTime.now(ZoneId.of("Asia/Kolkata"))
        LocalDate today = now.toLocalDate()

        if (now.getDayOfWeek() != DayOfWeek.SATURDAY && now.getDayOfWeek() != DayOfWeek.SUNDAY) {

            if (lastCheckedDate == null || !lastCheckedDate.isEqual(today)) {
                isMarketOpenToday = !isMarketHoliday(today)
                lastCheckedDate = today
            }

            if (isMarketOpenToday) {
                cacheNSEStockMarketData()
                cacheNSEOptionMarketData()
                cacheNSEIndexMarketData()
            }
        }
    }

    void cacheNSEStockMarketData() {
        String apiUrl = grailsApplication.config.market.api.url
        String apiPassword = grailsApplication.config.market.api.password


        Request request = new Request.Builder()
                .url(apiUrl+"admin/nse/stock/scan")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = HTTP_CLIENT.newCall(request).execute()) {
            if (!response.successful) {
                log.error("Error while caching nse stock market data. Response code: ${response.code()}")
            }
        } catch (Exception e) {
            log.error("Exception while triggering nse stock market data API", e)
        }

    }

    void cacheNSEOptionMarketData() {
        String apiUrl = grailsApplication.config.market.api.url
        String apiPassword = grailsApplication.config.market.api.password


        Request request = new Request.Builder()
                .url(apiUrl+"admin/nse/option/scan")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = HTTP_CLIENT.newCall(request).execute()) {
            if (!response.successful) {
                log.error("Error while caching nse option market data. Response code: ${response.code()}")
            }
        } catch (Exception e) {
            log.error("Exception while triggering nse option market data API", e)
        }

    }

    void cacheNSEIndexMarketData() {
        String apiUrl = grailsApplication.config.market.api.url
        String apiPassword = grailsApplication.config.market.api.password


        Request request = new Request.Builder()
                .url(apiUrl+"admin/nse/index/scan")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = HTTP_CLIENT.newCall(request).execute()) {
            if (!response.successful) {
                log.error("Error while caching nse index market data. Response code: ${response.code()}")
            }
        } catch (Exception e) {
            log.error("Exception while triggering nse index market data API", e)
        }

    }

    void nifty50StockCacheTrigger() {
        String apiUrl = grailsApplication.config.market.api.url
        String apiPassword = grailsApplication.config.market.api.password


        Request request = new Request.Builder()
                .url(apiUrl+"nifty_50_stock_analysis")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = HTTP_CLIENT.newCall(request).execute()) {
            if (!response.successful) {
                log.error("Error while caching nifty 50 stock data. Response code: ${response.code()}")
            }
        } catch (Exception e) {
            log.error("Exception while caching nifty 50 stock data", e)
        }
    }

    void getNseDataApiTrigger() {
        String apiUrl = grailsApplication.config.market.api.url
        String apiPassword = grailsApplication.config.market.api.password


        Request request = new Request.Builder()
                .url(apiUrl+"nse_data")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = HTTP_CLIENT.newCall(request).execute()) {
            if (!response.successful) {
                log.error("Error while fetching NSE data. Response code: ${response.code()}")

            }
        } catch (Exception e) {
            log.error("Exception while fetching NSE data", e)
        }
    }

    void preMarketApiTrigger() {
        String apiUrl = grailsApplication.config.market.api.url
        String apiPassword = grailsApplication.config.market.api.password


        Request request = new Request.Builder()
                .url(apiUrl+"pre_market_summary/refresh")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = HTTP_CLIENT.newCall(request).execute()) {
            if (response.successful) {
                fireBaseService.sendToTopic(
                        "Markets Open Soon 📈",
                        "Check today’s pre-market trends before the opening bell.",
                        "all"
                )
            } else {
                log.error("Error while caching pre market data. Response code: ${response.code()}")
            }
        } catch (Exception e) {
            log.error("Exception while caching pre market data", e)
        }
    }

    private static boolean isMarketHoliday(LocalDate today) {
        MarketHoliday.findByDate(today) != null
    }

    @Scheduled(cron = "0 30 6 * * ?", zone = "Asia/Kolkata")
    void refreshAndExpireIPOs() {
        log.info("Starting IPO refresh and expiration job")
        try {
            getIPOData()
        } catch (Exception e) {
            log.error("Error during IPO data fetch", e)
        }
        try {
            expireIPOs()
        } catch (Exception e) {
            log.error("Error during IPO expiration", e)
        }
        log.info("IPO refresh and expiration job completed")
    }

    void getIPOData() {
        String apiUrl = grailsApplication.config.ipo.api.url
        String apiKey = grailsApplication.config.ipo.api.key

        Request request = new Request.Builder()
                .url(apiUrl)
                .method("GET", null)
                .header("x-api-key", apiKey)
                .build()

        try (Response response = HTTP_CLIENT.newCall(request).execute()) {
            if (response.successful) {
                String body = response.body().string()
                def slurper = new JsonSlurper()
                def ipoList = slurper.parseText(body)

                if (ipoList instanceof List) {
                    IPOData.executeUpdate("DELETE FROM IPOData")

                    ipoList.each { ipo ->
                        try {
                            new IPOData(rawJson: JsonOutput.toJson(ipo)).save()
                        } catch (Exception e) {
                            log.error("Failed to save IPO record: ${ipo}", e)
                        }
                    }
                    IPOData.withSession { it.flush() }
                    log.info("Refreshed ${ipoList.size()} IPO records")
                } else {
                    log.error("IPO API returned unexpected format: ${body?.take(200)}")
                }
            } else {
                log.error("Error fetching IPO data. Response code: ${response.code()}")
            }
        } catch (Exception e) {
            log.error("Exception while fetching IPO data", e)
        }
    }

    void expireIPOs() {
        def slurper = new JsonSlurper()
        LocalDate today = LocalDate.now(ZoneId.of("Asia/Kolkata"))
        def dateFormats = [
                DateTimeFormatter.ofPattern("yyyy-MM-dd"),
                DateTimeFormatter.ofPattern("d MMM yyyy"),
                DateTimeFormatter.ofPattern("dd MMM yyyy"),
                DateTimeFormatter.ofPattern("MMM d, yyyy"),
                DateTimeFormatter.ofPattern("dd-MM-yyyy"),
                DateTimeFormatter.ofPattern("dd/MM/yyyy"),
                DateTimeFormatter.ofPattern("MM/dd/yyyy"),
                DateTimeFormatter.ofPattern("MMMM d, yyyy"),
                DateTimeFormatter.ofPattern("d MMMM yyyy"),
                DateTimeFormatter.ofPattern("dd-MMM-yyyy"),
                DateTimeFormatter.ISO_LOCAL_DATE,
        ]

        List<IPOData> allIpos = IPOData.list()
        int expiredCount = 0

        allIpos.each { IPOData ipoData ->
            try {
                def parsed = slurper.parseText(ipoData.rawJson)
                String status = parsed.status?.toString()?.toLowerCase()
                String endDateStr = parsed.endDate ?: parsed.end_date ?: parsed.close_date

                if (status == "open" && endDateStr) {
                    LocalDate endDate = parseDate(endDateStr, dateFormats)
                    if (endDate != null && endDate.isBefore(today)) {
                        parsed.status = "closed"
                        ipoData.rawJson = JsonOutput.toJson(parsed)
                        ipoData.save()
                        expiredCount++
                    }
                }
            } catch (Exception e) {
                log.error("Failed to process IPO record id=${ipoData.id}", e)
            }
        }

        if (expiredCount > 0) {
            IPOData.withSession { it.flush() }
        }
        log.info("Expired ${expiredCount} IPO records")
    }

    private static LocalDate parseDate(String dateStr, List<DateTimeFormatter> formats) {
        for (DateTimeFormatter fmt : formats) {
            try {
                return LocalDate.parse(dateStr.trim(), fmt)
            } catch (Exception ignored) {}
        }
        return null
    }

}
