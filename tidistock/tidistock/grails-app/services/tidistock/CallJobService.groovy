package tidistock

import grails.core.GrailsApplication
import grails.gorm.transactions.Transactional
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.scheduling.annotation.Scheduled
import okhttp3.*

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

@Transactional
class CallJobService {

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
            subscriptions.forEach {
                it.isSubscribed = false
                it.subscriptionType = null
                it.expirationDate = null
                it.save(flush: true)

                String fcmToken = User?.findByWallet(Wallet?.findBySubscription(it))?.fcmToken

                if (fcmToken) {
                    fireBaseService.sendToToken(
                            fcmToken,
                            "TIDI Membership Expired – Renew for ₹249",
                            "Your membership has expired. Renew now to continue enjoying premium TIDI features."
                    );
                }

            }
        }

    }

    @Scheduled(cron = "0 0 10 * * ?", zone = "Asia/Kolkata")
    void notifyExpiringSubscriptions() {
        LocalDate today = LocalDate.now(ZoneId.of("Asia/Kolkata"))

        // 🔹 Notify users whose subscription is expiring in 5 → 0 days
        (0..5).each { daysLeft ->
            LocalDate targetDate = today.plusDays(daysLeft)
            Date startOfDay = Date.from(targetDate.atStartOfDay(ZoneId.systemDefault()).toInstant())
            Date endOfDay = Date.from(targetDate.plusDays(1).atStartOfDay(ZoneId.systemDefault()).minusNanos(1).toInstant())

            List<Subscription> expiring = Subscription.findAllByExpirationDateBetweenAndIsSubscribed(
                    startOfDay, endOfDay, true
            )

            expiring.each { sub ->
                String fcmToken = User?.findByWallet(Wallet?.findBySubscription(sub))?.fcmToken

                if (fcmToken) {
                    fireBaseService.sendToToken(
                            fcmToken,
                            "TIDI Membership Expiring Soon – ₹249",
                            "Only ${daysLeft} day(s) left! Renew now and keep uninterrupted access to all premium TIDI features."
                    )
                }


            }
        }

        List<Subscription> expired = Subscription.findAllByIsSubscribed(false)
        expired.each { sub ->
            String fcmToken = User?.findByWallet(Wallet?.findBySubscription(sub))?.fcmToken

            if (fcmToken) {
                fireBaseService.sendToToken(
                        fcmToken,
                        "Get TIDI Membership – Just ₹249",
                        "Unlock all premium TIDI features instantly. Subscribe now for only ₹249."
                );

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

        OkHttpClient client = new OkHttpClient().newBuilder()
                .build()

        Request request = new Request.Builder()
                .url(apiUrl+"admin/nifty_option/refresh")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = client.newCall(request).execute()) {
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

        OkHttpClient client = new OkHttpClient().newBuilder()
                .build()

        Request request = new Request.Builder()
                .url(apiUrl+"admin/nse/stock/scan")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = client.newCall(request).execute()) {
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

        OkHttpClient client = new OkHttpClient().newBuilder()
                .build()

        Request request = new Request.Builder()
                .url(apiUrl+"admin/nse/option/scan")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = client.newCall(request).execute()) {
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

        OkHttpClient client = new OkHttpClient().newBuilder()
                .build()

        Request request = new Request.Builder()
                .url(apiUrl+"admin/nse/index/scan")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = client.newCall(request).execute()) {
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

        OkHttpClient client = new OkHttpClient().newBuilder()
                .build()

        Request request = new Request.Builder()
                .url(apiUrl+"nifty_50_stock_analysis")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = client.newCall(request).execute()) {
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

        OkHttpClient client = new OkHttpClient().newBuilder()
                .build()

        Request request = new Request.Builder()
                .url(apiUrl+"nse_data")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = client.newCall(request).execute()) {
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

        OkHttpClient client = new OkHttpClient().newBuilder()
                .build()

        Request request = new Request.Builder()
                .url(apiUrl+"pre_market_summary/refresh")
                .method("GET", null)
                .header("authorization", "Bearer ${apiPassword}")
                .build()

        try (Response response = client.newCall(request).execute()) {
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


}
