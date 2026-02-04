package tidistock

import java.time.LocalDate

class MarketHoliday {

    LocalDate date
    String day
    String occasion


    static constraints = {
        date nullable: false, unique: true
        day nullable: false, blank: false
        occasion nullable: false
    }
}
