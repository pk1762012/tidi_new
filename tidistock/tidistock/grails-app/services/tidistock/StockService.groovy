package tidistock

import grails.gorm.PagedResultList
import groovy.json.JsonSlurper
import tidistock.enums.OrderType
import tidistock.enums.PortfolioLogAction
import tidistock.enums.StockRecommendationStatus
import tidistock.enums.StockRecommendationType
import tidistock.requestbody.CSVFile
import grails.gorm.transactions.Transactional
import grails.plugin.springsecurity.annotation.Secured
import io.micronaut.http.HttpStatus
import org.springframework.web.multipart.MultipartFile
import tidistock.requestbody.GetStockRecommendationPayload
import tidistock.requestbody.PaginationPayload
import tidistock.requestbody.StockRecommendationPayload
import tidistock.requestbody.StockRecommendationUpdatePayload

import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Transactional
@Secured(['ROLE_ADMIN', 'ROLE_USER'])
class StockService {

    def messageSource

    def springSecurityService

    def fireBaseService

    def uploadStockData(CSVFile csvFile) {
        MultipartFile multipartFile = csvFile.file

        Stock.executeUpdate("DELETE FROM Stock")

        multipartFile.inputStream.withReader { reader ->
            boolean headerSkipped = false
            reader.eachLine { line ->
                if (!headerSkipped) {
                    headerSkipped = true
                    return // skip CSV header
                }
                def columns = line.split(",")*.trim() // simple CSV split
                if (columns.size() >= 4) {
                    def stock = new Stock(
                            symbol: columns[0],
                            name: columns[1]
                    )
                    stock.save(failOnError: true)
                }
            }
        }
        return  [status: true, code: HttpStatus.OK.getCode(), message: messageSource.getMessage('stock.data.upload.success', new Object[] { }, Locale.ENGLISH)]


    }

    def uploadNifty50Stocks(CSVFile csvFile) {
        MultipartFile multipartFile = csvFile.file

        Stock.executeUpdate("DELETE FROM Nifty50Stock")

        multipartFile.inputStream.withReader { reader ->
            boolean headerSkipped = false
            reader.eachLine { line ->
                if (!headerSkipped) {
                    headerSkipped = true
                    return // skip CSV header
                }
                def columns = line.split(",")*.trim() // simple CSV split
                if (columns.size() >= 4) {
                    def stock = new Nifty50Stock(
                            symbol: columns[0]?.replaceAll('"', ''),
                            name: Stock?.findAllBySymbol(columns[0]?.replaceAll('"', '') as String)?.name
                    )
                    stock.save(failOnError: true)
                }
            }
        }
        return  [status: true, code: HttpStatus.OK.getCode(), message: messageSource.getMessage('stock.data.upload.success', new Object[] { }, Locale.ENGLISH)]


    }

    def uploadNiftyFNOStocks(CSVFile csvFile) {
        MultipartFile multipartFile = csvFile.file

        Stock.executeUpdate("DELETE FROM NiftyFNOStock")

        multipartFile.inputStream.withReader { reader ->
            boolean headerSkipped = false
            reader.eachLine { line ->
                if (!headerSkipped) {
                    headerSkipped = true
                    return // skip CSV header
                }
                def columns = line.split(",")*.trim() // simple CSV split
                if (columns.size() >= 4) {
                    def stock = new NiftyFNOStock(
                            symbol: columns[0]?.replaceAll('"', ''),
                            name: Stock?.findAllBySymbol(columns[0]?.replaceAll('"', '') as String)?.name
                    )
                    stock.save(failOnError: true)
                }
            }
        }
        return  [status: true, code: HttpStatus.OK.getCode(), message: messageSource.getMessage('stock.data.upload.success', new Object[] { }, Locale.ENGLISH)]


    }

    def uploadEtfData(CSVFile csvFile) {
        MultipartFile multipartFile = csvFile.file

        ETF.executeUpdate("DELETE FROM ETF")

        multipartFile.inputStream.withReader { reader ->
            boolean headerSkipped = false
            reader.eachLine { line ->
                if (!headerSkipped) {
                    headerSkipped = true
                    return // skip CSV header
                }
                def columns = line.split(",")*.trim() // simple CSV split
                if (columns.size() >= 4) {
                    def etf = new ETF(
                            symbol: columns[0],
                            underlying: columns[1],
                            name: columns[2]
                    )
                    etf.save(failOnError: true)
                }
            }
        }
        return  [status: true, code: HttpStatus.OK.getCode(), message: messageSource.getMessage('stock.data.upload.success', new Object[] { }, Locale.ENGLISH)]
    }

    def searchStock(String query) {
        User user = springSecurityService.getCurrentUser()

        Class domainClass = Stock
        String q = "%${query?.trim()}%"

        def results = domainClass.createCriteria().list {
            or {
                ilike("name", q)
                ilike("symbol", q)
            }
            maxResults(20)  // dropdown limit
            order("name", "asc")
        }

        return results
    }

    def searchEtf(String query) {
        def results = ETF.createCriteria().list {
            or {
                ilike("name", "%${query}%")
                ilike("underlying", "%${query}%")
                ilike("symbol", "%${query}%")
            }
            maxResults(20) // limit results for dropdown
            order("name", "asc")
        }

        return results
    }

    def getHolidayList() {
        return MarketHoliday.list()
    }

    def uploadHolidayData(CSVFile csvFile) {
        MultipartFile multipartFile = csvFile.file

        MarketHoliday.executeUpdate("delete from MarketHoliday")

        def dateFormat = DateTimeFormatter.ofPattern("d/M/yyyy") // match your CSV

        multipartFile.inputStream.withReader { reader ->
            boolean headerSkipped = false
            reader.eachLine { line ->
                if (!headerSkipped) {
                    headerSkipped = true
                    return // skip CSV header
                }

                def columns = line.split(",")*.trim()
                if (columns.size() >= 4) {
                    try {
                        def dateString = columns[1].replaceAll("[^0-9/]", "")
                        LocalDate holidayDate = LocalDate.parse(dateString, dateFormat)

                        def holiday = new MarketHoliday(
                                date: holidayDate,
                                day: columns[2]?.replaceAll('"', ''),
                                occasion: columns[3]?.replaceAll('"', '')
                        )
                        holiday.save(failOnError: true)
                    } catch (Exception e) {
                        log.error("Failed to save holiday for line: ${line}", e)
                    }
                } else {
                    log.warn("Skipping invalid line: ${line}")
                }
            }
        }

        return  [status: true, code: HttpStatus.OK.getCode(), message: messageSource.getMessage('stock.data.upload.success', new Object[] { }, Locale.ENGLISH)]
    }

    @Secured(['ROLE_ADMIN'])
    def createStockRecommendation(StockRecommendationPayload payload) {

        Stock stock = Stock.findBySymbol(payload.getStock())

        if (stock) {

            if (!StockRecommend.findAllByStockSymbolAndStockRecommendationStatus(stock.symbol, StockRecommendationStatus.LIVE).isEmpty()) {
                return [
                        status : false,
                        code   : HttpStatus.BAD_REQUEST.getCode(),
                        message: messageSource.getMessage('stock.recommend.active.present', new Object[]{}, Locale.ENGLISH)
                ]
            }


            StockRecommend stockRecommend = new StockRecommend()
            stockRecommend.startDate = payload.startDate
            stockRecommend.stockName = stock.name
            stockRecommend.stockSymbol = stock.symbol
            stockRecommend.triggerPrice = payload.triggerPrice
            stockRecommend.targetPrice = payload.targetPrice
            stockRecommend.stopLoss = payload.stopLoss
            stockRecommend.stockRecommendationStatus = StockRecommendationStatus.LIVE
            stockRecommend.type = payload.type

            stockRecommend = stockRecommend.save(flush: true)

            fireBaseService.sendToTopic(
                    "Fresh Stock Recommendation",
                    "View the latest update in the advisory section.",
                    "all"
            )

            return stockRecommendationResponse(stockRecommend)

        } else {
            return [
                    status : false,
                    code   : HttpStatus.BAD_REQUEST.getCode(),
                    message: messageSource.getMessage('stock.data.not.present', new Object[]{}, Locale.ENGLISH)
            ]
        }
    }

    @Secured(['ROLE_ADMIN'])
    def updateStockRecommendation(String id, StockRecommendationUpdatePayload payload) {
        StockRecommend stockRecommend = StockRecommend.findById(id)

        if (!stockRecommend) {
            return [
                    status : false,
                    code   : HttpStatus.BAD_REQUEST.getCode(),
                    message: messageSource.getMessage('stock.recommend.not.found', new Object[]{}, Locale.ENGLISH)
            ]
        }

        stockRecommend.targetPrice = payload.targetPrice
        stockRecommend.triggerPrice = payload.triggerPrice
        stockRecommend.stopLoss = payload.stopLoss

        stockRecommend = stockRecommend.save(flush : true)

        return stockRecommendationResponse(stockRecommend)

    }

    private LinkedHashMap<String, Serializable> stockRecommendationResponse(StockRecommend stockRecommend) {
        [
                status : true,
                code   : HttpStatus.OK.getCode(),
                data   : ["id"                       : stockRecommend.id,
                          "startDate"                : stockRecommend.startDate,
                          "triggerPrice"             : stockRecommend.triggerPrice,
                          "dateCreated"              : stockRecommend.dateCreated,
                          "stockRecommendationStatus": stockRecommend.stockRecommendationStatus,
                          "lastUpdated"              : stockRecommend.lastUpdated,
                          "stock"                    : [
                                  "name"  : stockRecommend.stockName,
                                  "symbol": stockRecommend.stockSymbol
                          ],
                          "stopLoss"                 : stockRecommend.stopLoss,
                          "targetPrice"              : stockRecommend.targetPrice,
                          "bookedPrice"              : stockRecommend.bookedPrice,
                          "type"                     : stockRecommend.type
                ],
                message: messageSource.getMessage('stock.recommend.saved', new Object[]{}, Locale.ENGLISH)
        ]
    }

    @Secured(['ROLE_ADMIN'])
    def bookStockRecommendation(String id, BigDecimal price) {
        StockRecommend stockRecommend = StockRecommend.findById(id)

        if (!stockRecommend) {
            return [
                    status : false,
                    code   : HttpStatus.BAD_REQUEST.getCode(),
                    message: messageSource.getMessage('stock.recommend.not.found', new Object[]{}, Locale.ENGLISH)
            ]
        }

        stockRecommend.bookedPrice = price
        stockRecommend.stockRecommendationStatus =  price > stockRecommend.triggerPrice ? StockRecommendationStatus.BOOKED_PROFIT : StockRecommendationStatus.BOOKED_LOSS

        stockRecommend = stockRecommend.save(flush : true)

        fireBaseService.sendToTopic(
                "${stockRecommend.stockSymbol}: ${stockRecommend.stockRecommendationStatus == StockRecommendationStatus.BOOKED_PROFIT ? 'Target Hit – Profit Booked' : 'Stop Hit – Loss Booked'}",
                "Review trade outcome in the advisory section.",
                "all"
        )

        return stockRecommendationResponse(stockRecommend)
    }

    @Secured(['ROLE_ADMIN'])
    def deleteStockRecommendation(String id) {
        StockRecommend stockRecommend = StockRecommend.findById(id)

        if (!stockRecommend) {
            return [
                    status : false,
                    code   : HttpStatus.BAD_REQUEST.getCode(),
                    message: messageSource.getMessage('stock.recommend.not.found', new Object[]{}, Locale.ENGLISH)
            ]
        }

        stockRecommend.delete(flush: true)

        return [
                status : true,
                code   : HttpStatus.NO_CONTENT.getCode(),
                message: messageSource.getMessage('stock.recommend.deleted', new Object[]{}, Locale.ENGLISH)
        ]
    }

    @Transactional(readOnly = true)
    def getStockRecommendations(GetStockRecommendationPayload payload) {

        User user = springSecurityService.getCurrentUser()
        def isAdmin = UserRole.exists(user.id, Role.findByAuthority('ROLE_ADMIN').id)

        int limit = payload.limit ?: 10
        int offset = payload.offset ?: 0
        String sortField = payload.sortField ?: "dateCreated"
        String sortOrder = payload.sortOrder?.toLowerCase() == "asc" ? "asc" : "desc"
        String stockFilter = payload.stock?.trim()
        StockRecommendationStatus status = payload.status
        StockRecommendationType type = payload.type

        def criteria = StockRecommend.createCriteria()
        PagedResultList result = criteria.list(max: limit, offset: offset) {

            if (stockFilter) {
                eq("stockSymbol", stockFilter)
            }

            if (status) {
                eq("stockRecommendationStatus", status)
            }

            if (type) {
                eq("type", type)
            }

            if (sortField && sortOrder) {
                order(sortField, sortOrder)
            }

        } as PagedResultList

        def data = result.collect { StockRecommend stockRecommend ->
            [
             "id"                       : stockRecommend.id,
             "startDate"                : stockRecommend.startDate,
             "triggerPrice"             : stockRecommend.triggerPrice,
             "dateCreated"              : stockRecommend.dateCreated,
             "stockRecommendationStatus": stockRecommend.stockRecommendationStatus,
             "lastUpdated"              : stockRecommend.lastUpdated,
             "stockName"                : (isAdmin || (user.wallet.subscription.isSubscribed || !stockRecommend.stockRecommendationStatus.equals(StockRecommendationStatus.LIVE))) ? stockRecommend.stockName : '',
             "stockSymbol"              : (isAdmin || (user.wallet.subscription.isSubscribed || !stockRecommend.stockRecommendationStatus.equals(StockRecommendationStatus.LIVE))) ? stockRecommend.stockSymbol : '',
             "stopLoss"                 : stockRecommend.stopLoss,
             "targetPrice"              : stockRecommend.targetPrice,
             "bookedPrice"              : stockRecommend.bookedPrice,
             "type"                     : stockRecommend.type
            ]
        }

        return [
                limit     : limit,
                offset    : offset,
                totalCount: result.totalCount,
                data      : data
        ]
    }

    @Secured(['ROLE_ADMIN'])
    def createPortfolioStock(String stockSymbol) {

        Stock stock = Stock.findBySymbol(stockSymbol)

        if (stock) {

            if (Portfolio.findByStockSymbol(stock.symbol)) {
                return [
                        status : false,
                        code   : HttpStatus.BAD_REQUEST.getCode(),
                        message: messageSource.getMessage('stock.portfolio.present', new Object[]{}, Locale.ENGLISH)
                ]
            }


            Portfolio portfolio = new Portfolio()
            portfolio.stockName = stock.name
            portfolio.stockSymbol = stock.symbol

            portfolio.save(flush: true)

            PortfolioLog portfolioLog = new PortfolioLog()
            portfolioLog.stockName = stock.name
            portfolioLog.stockSymbol = stock.symbol
            portfolioLog.action = PortfolioLogAction.ADDED

            portfolioLog.save(flush: true)


            fireBaseService.sendToTopic(
                    "Portfolio rebalancing update",
                    "Important changes have been made to the TIDI Wealth portfolio. Review the updates now.",
                    "all"
            )

            return [
                    status : true,
                    code   : HttpStatus.CREATED.getCode(),
                    message: messageSource.getMessage('stock.portfolio.created', new Object[]{}, Locale.ENGLISH)
            ]

        } else {
            return [
                    status : false,
                    code   : HttpStatus.BAD_REQUEST.getCode(),
                    message: messageSource.getMessage('stock.data.not.present', new Object[]{}, Locale.ENGLISH)
            ]
        }
    }

    @Secured(['ROLE_ADMIN'])
    def deletePortfolioStock(String id) {
        Portfolio portfolio = Portfolio.findById(id)

        if (!portfolio) {
            return [
                    status : false,
                    code   : HttpStatus.BAD_REQUEST.getCode(),
                    message: messageSource.getMessage('stock.portfolio.not.found', new Object[]{}, Locale.ENGLISH)
            ]
        }

        PortfolioLog portfolioLog = new PortfolioLog()
        portfolioLog.stockName = portfolio.stockName
        portfolioLog.stockSymbol = portfolio.stockSymbol
        portfolioLog.action = PortfolioLogAction.REMOVED

        portfolioLog.save(flush: true)

        portfolio.delete(flush: true)

        fireBaseService.sendToTopic(
                "Portfolio rebalancing update",
                "Important changes have been made to your TIDI Wealth portfolio. Review the updates now.",
                "all"
        )

        return [
                status : true,
                code   : HttpStatus.NO_CONTENT.getCode(),
                message: messageSource.getMessage('stock.portfolio.deleted', new Object[]{}, Locale.ENGLISH)
        ]
    }

    @Transactional(readOnly = true)
    def getStockPortfolio() {
        return Portfolio.list()
    }

    @Transactional(readOnly = true)
    def getPortfolioHistory(PaginationPayload paginationPayload) {
        int limit = paginationPayload.limit ?: 10
        int offset = paginationPayload.offset ?: 0

        PagedResultList result = PortfolioLog.createCriteria().list(max: limit, offset: offset) {
            order("dateCreated", "desc")
        } as PagedResultList

        return [
                limit     : limit,
                offset    : offset,
                totalCount: result.totalCount,
                data      : result
        ]
    }

    @Transactional(readOnly = true)
    List getIPODataList() {

        def slurper = new JsonSlurper()
        LocalDate today = LocalDate.now(ZoneId.of("Asia/Kolkata"))
        def dateFormats = [
                DateTimeFormatter.ofPattern("yyyy-MM-dd"),
                DateTimeFormatter.ofPattern("d MMM yyyy"),
                DateTimeFormatter.ofPattern("dd MMM yyyy"),
                DateTimeFormatter.ofPattern("MMM d, yyyy"),
                DateTimeFormatter.ofPattern("dd-MM-yyyy")
        ]

        IPOData.list().collect { IPOData ipo ->
            def parsed = slurper.parseText(ipo.rawJson)
            String status = parsed.status?.toString()?.toLowerCase()
            String endDateStr = parsed.endDate ?: parsed.end_date ?: parsed.close_date

            if (status == "open" && endDateStr) {
                LocalDate endDate = tryParseDate(endDateStr, dateFormats)
                if (endDate != null && endDate.isBefore(today)) {
                    parsed.status = "closed"
                }
            }

            parsed
        }.findAll { it ->
            String s = it.status?.toString()?.toLowerCase()
            s == "open" || s == "upcoming"
        }
    }

    private static LocalDate tryParseDate(String dateStr, List<DateTimeFormatter> formats) {
        for (DateTimeFormatter fmt : formats) {
            try {
                return LocalDate.parse(dateStr.trim(), fmt)
            } catch (Exception ignored) {}
        }
        return null
    }

    @Transactional(readOnly = true)
    def getFIIData(PaginationPayload paginationPayload) {
        int limit = paginationPayload.limit ?: 10
        int offset = paginationPayload.offset ?: 0

        PagedResultList result = FII_DII_Data.createCriteria().list(max: limit, offset: offset) {
            order("date", "desc")
        } as PagedResultList

        return [
                limit     : limit,
                offset    : offset,
                totalCount: result.totalCount,
                data      : result
        ]
    }

    }
