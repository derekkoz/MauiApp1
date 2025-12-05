IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'kozderek@gmail.com')
  CREATE LOGIN [kozderek@gmail.com] FROM EXTERNAL PROVIDER;
GO
BEGIN TRY
  GRANT EXECUTE ON OBJECT::sys.sp_getapplock TO [kozderek@gmail.com];
END TRY
BEGIN CATCH
  PRINT 'Skipping sp_getapplock GRANT: ' + ERROR_MESSAGE();
END CATCH;
GO
