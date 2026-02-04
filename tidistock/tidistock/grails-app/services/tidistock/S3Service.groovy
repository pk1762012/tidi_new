package tidistock


import grails.core.GrailsApplication
import io.micronaut.http.HttpStatus
import org.springframework.context.MessageSource
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.multipart.MultipartFile
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider
import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.s3.S3Client
import software.amazon.awssdk.services.s3.model.*
import tidistock.requestbody.PANUploadPayload

import java.nio.file.Files

@Transactional
class S3Service {

        def springSecurityService

        GrailsApplication grailsApplication

        S3Client s3Client

        MessageSource messageSource



        void init() {
            String accessKey = grailsApplication.config.getProperty("aws.s3.accessKey")
            String secretKey = grailsApplication.config.getProperty("aws.s3.secretKey")
            String region = grailsApplication.config.getProperty("aws.s3.region")
            AwsBasicCredentials awsCredentials = AwsBasicCredentials.create(accessKey, secretKey)
            s3Client = S3Client.builder()
                    .credentialsProvider(StaticCredentialsProvider.create(awsCredentials))
                    .region(Region.of(region))
                    .build()
        }

        def uploadProfilePicture(MultipartFile file) {
            User user = springSecurityService.getCurrentUser()
            String bucketName = grailsApplication.config.getProperty("aws.s3.bucketName")
            String currentFileName = "USERS/" + user.id + "/PROFILE_PICTURE/" + user.profilePictureFile
            String newFileName = "USERS/" + user.id + "/PROFILE_PICTURE/" + file.originalFilename
            try {
                if (user.profilePictureFile && fileExists(bucketName, currentFileName)) {
                    deleteFile(bucketName, currentFileName)
                }

                File tempFile = Files.createTempFile(null, null).toFile()
                file.transferTo(tempFile)

                PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                        .bucket(bucketName)
                        .key(newFileName)
                        .build()

                s3Client.putObject(putObjectRequest, tempFile.toPath())
                tempFile.delete()

                user.profilePictureFile = file.originalFilename
                user.save(Flush : true)

                return [status: true, code: HttpStatus.OK.getCode(), message : messageSource.getMessage('profile.upload.success', new Object[] { }, Locale.ENGLISH)]
            } catch (Exception e) {
                e.printStackTrace()
                throw new RuntimeException(messageSource.getMessage('profile.upload.failure', new Object[] { }, Locale.ENGLISH), e)
            }
        }

    def uploadPANDetails(PANUploadPayload payload) {
        User user = springSecurityService.getCurrentUser()
        String bucketName = grailsApplication.config.getProperty("aws.s3.bucketName")
        String newFileName = "USERS/" + user.id + "/PAN/" + payload.file.originalFilename
        try {

            File tempFile = Files.createTempFile(null, null).toFile()
            payload.file.transferTo(tempFile)

            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(bucketName)
                    .key(newFileName)
                    .build()

            s3Client.putObject(putObjectRequest, tempFile.toPath())
            tempFile.delete()

            user.email = payload.email
            user.pan = payload.pan
            user.save(Flush : true)

            return [status: true, code: HttpStatus.OK.getCode(), message : messageSource.getMessage('pan.upload.success', new Object[] { }, Locale.ENGLISH)]
        } catch (Exception e) {
            e.printStackTrace()
            throw new RuntimeException(messageSource.getMessage('pan.upload.failure', new Object[] { }, Locale.ENGLISH), e)
        }
    }

        boolean fileExists(String bucketName, String fileName) {
            try {
                HeadObjectRequest headObjectRequest = HeadObjectRequest.builder()
                        .bucket(bucketName)
                        .key(fileName)
                        .build()
                HeadObjectResponse headObjectResponse = s3Client.headObject(headObjectRequest)
                return headObjectResponse != null
            } catch (NoSuchKeyException e) {
                return false
            } catch (Exception e) {
                e.printStackTrace()
                throw new RuntimeException(messageSource.getMessage('profile.file.check.error', new Object[] { }, Locale.ENGLISH), e)
            }
        }

        void deleteFile(String bucketName, String fileName) {
            try {
                DeleteObjectRequest deleteObjectRequest = DeleteObjectRequest.builder()
                        .bucket(bucketName)
                        .key(fileName)
                        .build()
                s3Client.deleteObject(deleteObjectRequest)
            } catch (Exception e) {
                e.printStackTrace()
                throw new RuntimeException(messageSource.getMessage('profile.delete.error', new Object[] { }, Locale.ENGLISH), e)
            }
        }

}
