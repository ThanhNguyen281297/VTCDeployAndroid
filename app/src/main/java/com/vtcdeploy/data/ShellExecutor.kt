package com.vtcdeploy.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader

class ShellExecutor(private val context: Context) {

    suspend fun execute(command: String, timeoutMs: Long = 60000): Result<String> = withContext(Dispatchers.IO) {
        try {
            val processBuilder = ProcessBuilder("su", "-c", command)
            processBuilder.redirectErrorStream(true)
            val process = processBuilder.start()

            val output = StringBuilder()
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            var line: String?
            val startTime = System.currentTimeMillis()

            while (true) {
                if (System.currentTimeMillis() - startTime > timeoutMs) {
                    process.destroy()
                    return@withContext Result.failure(TimeoutException("Command timed out: $command"))
                }
                line = reader.readLine()
                if (line == null) break
                output.append(line).append('\n')
            }

            val exitCode = process.waitFor()
            if (exitCode == 0) {
                Result.success(output.toString())
            } else {
                Result.failure(RuntimeException("Command failed (exit $exitCode): $command\n$output"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun executeNoWait(command: String): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            Runtime.getRuntime().exec(arrayOf("su", "-c", command))
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}