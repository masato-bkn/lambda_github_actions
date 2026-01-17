exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));
  console.log('version: 3');
  const response = {
    statusCode: 200,
    body: JSON.stringify({
      message: 'Hello from Lambda!',
      timestamp: new Date().toISOString(),
    }),
  };

  return response;
};
